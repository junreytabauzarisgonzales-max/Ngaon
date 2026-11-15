import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';

Future<String> fileLoader(String name) => File('assets/mock/$name').readAsString();

Future<MockBackend> backend(GoApp app) async {
  final b = MockBackend(app: app, loader: fileLoader, speed: 0.01);
  await b.init();
  return b;
}

Future<T> next<T extends WsEvent>(MockBackend b, {bool Function(T)? where}) =>
    b.outgoing.map(WsEvent.parse).where((e) => e is T && (where == null || where(e))).cast<T>().first.timeout(const Duration(seconds: 5));

void main() {
  test('OTP: wrong code rejected, 123456 accepted; 1111 = new user', () async {
    final b = await backend(GoApp.customer);
    expect(() => b.verifyOtp('+639171234567', '000000', GoApp.customer), throwsA(isA<ApiException>()));
    expect(b.verifyOtp('+639171231111', '123456', GoApp.customer)['is_new_user'], isTrue);
    b.dispose();
  });

  test('merchant numbers ending 0000 are forbidden', () async {
    final b = await backend(GoApp.merchant);
    b.simulate = false;
    b.verifyOtp('+639170000000', '123456', GoApp.merchant);
    expect(b.merchantMe, throwsA(isA<ApiException>().having((e) => e.code, 'code', 'forbidden')));
    b.dispose();
  });

  test('customer: ride walks through every status to completed', () async {
    final b = await backend(GoApp.customer);
    final repo = MockJobsRepository(b);
    b.verifyOtp('+639171234567', '123456', GoApp.customer);
    final req = QuoteRequest(
      service: ServiceType.ride,
      pickup: Stop(address: 'A', location: LatLng.bongao),
      dropoff: Stop(address: 'B', location: const LatLng(lat: 5.0362, lng: 119.7795)),
    );
    final q = await repo.quote(req);
    expect(q.totalCentavos, greaterThan(0));
    final seen = <JobStatus>[];
    final sub = b.outgoing
        .map(WsEvent.parse)
        .where((e) => e is JobUpdatedEvent)
        .cast<JobUpdatedEvent>()
        .listen((e) => seen.add(e.job.status));
    final job = await repo.create(quoteId: q.id, method: PaymentMethod.cash, idempotencyKey: 'k1');
    // idempotent retry returns the same job
    expect((await repo.create(quoteId: q.id, method: PaymentMethod.cash, idempotencyKey: 'k1')).id, job.id);
    await next<RiderLocationEvent>(b);
    await next<JobUpdatedEvent>(b, where: (e) => e.job.status == JobStatus.completed);
    await sub.cancel();
    expect(
      seen,
      containsAllInOrder([
        JobStatus.riderAssigned,
        JobStatus.arrivedPickup,
        JobStatus.pickedUp,
        JobStatus.arrivedDropoff,
        JobStatus.completed,
      ]),
    );
    expect((await repo.get(job.id)).can(JobActions.rate), isTrue);
    b.dispose();
  });

  test('customer: pabili pauses at items_purchased until confirm-items', () async {
    final b = await backend(GoApp.customer);
    final repo = MockJobsRepository(b);
    b.verifyOtp('+639171234567', '123456', GoApp.customer);
    final q = await repo.quote(
      QuoteRequest(
        service: ServiceType.pabili,
        pickup: Stop(address: 'Market', location: LatLng.bongao),
        dropoff: Stop(address: 'Home', location: const LatLng(lat: 5.0251, lng: 119.7769)),
        pabili: PabiliQuoteInput(
          storeName: 'Market',
          items: [PabiliItem(name: 'Eggs', quantity: 12)],
          estimatedItemTotalCentavos: 20000,
        ),
      ),
    );
    expect(q.maxItemBudgetCentavos, isNotNull);
    final job = await repo.create(quoteId: q.id, method: PaymentMethod.cash, idempotencyKey: 'p1');
    final purchased = await next<JobUpdatedEvent>(b, where: (e) => e.job.status == JobStatus.itemsPurchased);
    expect(purchased.job.can(JobActions.confirmItems), isTrue);
    expect(purchased.job.pabili!.receiptUrl, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect((await repo.get(job.id)).status, JobStatus.itemsPurchased, reason: 'waits for the customer');
    expect((await repo.confirmItems(job.id, true)).status, JobStatus.pickedUp);
    b.dispose();
  });

  test('quote outside service area is rejected', () async {
    final b = await backend(GoApp.customer);
    b.verifyOtp('+639171234567', '123456', GoApp.customer);
    expect(
      () => b.quote(
        QuoteRequest(
          service: ServiceType.ride,
          pickup: Stop(address: 'Jolo', location: const LatLng(lat: 6.05, lng: 121.0)),
          dropoff: Stop(address: 'B', location: LatLng.bongao),
        ).toJson(),
      ),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'out_of_service_area')),
    );
    b.dispose();
  });

  test('rider: online -> offer -> accept -> steps -> completed with proof', () async {
    final b = await backend(GoApp.rider);
    final repo = MockRiderRepository(b);
    b.verifyOtp('+639181112222', '123456', GoApp.rider);
    await repo.setStatus(online: true, location: LatLng.bongao);
    final offer = (await next<OfferNewEvent>(b)).offer;
    var job = await repo.acceptOffer(offer.id);
    expect(job.status, JobStatus.riderAssigned);
    while (job.status != JobStatus.completed) {
      final step = riderNextStep(job);
      if (step == null) {
        job = (await next<JobUpdatedEvent>(b, where: (e) => e.job.id == job.id && riderNextStep(e.job) != null)).job;
        continue;
      }
      if (step.target == JobStatus.completed && step.needsProofPhoto) {
        expect(
          () => b.riderUpdateStatus(job.id, {'status': 'completed', 'location': LatLng.bongao.toJson()}),
          throwsA(isA<ApiException>()),
        );
      }
      job = await repo.updateJobStatus(
        job.id,
        status: step.target,
        location: LatLng.bongao,
        proofKey: step.needsProofPhoto ? 'k/proof.jpg' : null,
        receiptKey: step.needsReceipt ? 'k/receipt.jpg' : null,
        itemTotalCentavos: step.needsReceipt ? 45000 : null,
      );
    }
    expect(await repo.activeJob(), isNull);
    final txs = await repo.transactions();
    expect(txs.items.first.type, WalletTxType.commission);
    b.dispose();
  });

  test('rider: cannot go online below minimum balance', () async {
    final b = await backend(GoApp.rider);
    b.verifyOtp('+639181112222', '123456', GoApp.rider);
    b.riderProfile['balance_centavos'] = 0;
    expect(() => b.setRiderStatus(true), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'insufficient_balance')));
    b.dispose();
  });

  test('merchant: order.new -> accept -> rider assigned -> ready -> picked up', () async {
    final b = await backend(GoApp.merchant);
    final repo = MockMerchantAdminRepository(b);
    b.verifyOtp('+639193334444', '123456', GoApp.merchant);
    final order = (await next<OrderNewEvent>(b)).order;
    expect(order.status, MerchantOrderStatus.newOrder);
    expect(order.merchantAcceptDeadline, isNotNull);
    final accepted = await repo.accept(order.id, 15);
    expect(accepted.status, MerchantOrderStatus.preparing);
    await expectLater(repo.accept(order.id, 15), throwsA(isA<ApiException>().having((e) => e.code, 'c', 'order_already_handled')));
    await next<OrderUpdatedEvent>(b, where: (e) => e.order.id == order.id && e.order.rider != null);
    expect((await repo.markReady(order.id)).status, MerchantOrderStatus.ready);
    await next<OrderUpdatedEvent>(b, where: (e) => e.order.id == order.id && e.order.status == MerchantOrderStatus.pickedUp);
    b.dispose();
  });

  test('merchant menu: create, availability, delete non-empty category fails', () async {
    final b = await backend(GoApp.merchant);
    b.simulate = false;
    final repo = MockMerchantAdminRepository(b);
    b.verifyOtp('+639193334444', '123456', GoApp.merchant);
    final menu = await repo.menu();
    await expectLater(repo.deleteCategory(menu.first.id), throwsA(isA<ApiException>()));
    final cat = await repo.addCategory('Desserts');
    final item = await repo.createItem(
      MenuItemInput(
        categoryId: cat.id,
        name: 'Leche flan',
        priceCentavos: 6000,
        isAvailable: true,
        addonGroups: [
          AddonGroupInput(
            name: 'Size',
            minSelect: 1,
            maxSelect: 1,
            options: [AddonOptionInput(name: 'Big', priceCentavos: 2000, isAvailable: true)],
          ),
        ],
      ),
    );
    expect(item.addonGroups.single.options.single.id, isNotEmpty);
    expect((await repo.setItemAvailability(item.id, false)).isAvailable, isFalse);
    await repo.reorderCategories([cat.id, ...menu.map((c) => c.id)]);
    expect((await repo.menu()).first.id, cat.id);
    b.dispose();
  });
}
