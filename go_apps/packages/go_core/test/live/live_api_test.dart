// Live contract test: drives the real HTTP repositories + WebSocket client
// against a running Go backend. Skipped unless GO_API is set, e.g.
//   GO_API=http://127.0.0.1:18080 flutter test test/live/live_api_test.dart
// Requires the backend's dev settings: DEV_OTP_CODE=123456,
// AUTO_APPROVE_RIDERS_SECONDS>0, RIDER_START_BALANCE>=10000.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';
import 'package:go_core/repositories/http/http_repositories.dart';

final base = Platform.environment['GO_API'];

class Party {
  Party(GoApp app) {
    final cfg = AppConfig(app: app, apiBaseUrl: base, wsUrl: base!.replaceFirst('http', 'ws'), useMockApi: false, enablePlatformPlugins: false);
    AppConfig.current = cfg;
    session = SessionStore(MemorySecureKeyValue());
    api = ApiClient(config: cfg, session: session, languageCode: () => 'en', onSessionExpired: () async {});
    auth = HttpAuthRepository(api);
  }
  late final SessionStore session;
  late final ApiClient api;
  late final HttpAuthRepository auth;

  Future<AuthResult> login(String phone, GoApp app, {String? name}) async {
    await auth.requestOtp(phone);
    final r = await auth.verifyOtp(phone, '123456', app);
    await session.save(r.accessToken, r.refreshToken);
    if (name != null && r.isNewUser) await auth.updateMe(name: name);
    return r;
  }
}

Future<String> upload(HttpUploadsRepository repo, UploadPurpose p) async {
  final t = await repo.create(p);
  await repo.put(t.uploadUrl, Uint8List.fromList([0xff, 0xd8, 1, 2, 3]));
  return t.key;
}

void main() {
  final skip = base == null ? 'set GO_API to run' : null;
  final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
  String phone(int n) => '+63917${(stamp * 10 + n).toString().padLeft(7, '0')}';
  const bongao = LatLng(lat: 5.0294, lng: 119.7730);

  test('customer + merchant + rider over real HTTP and WebSocket', () async {
    // --- merchant (seeded owner number)
    final m = Party(GoApp.merchant);
    await m.login('+639193334444', GoApp.merchant);
    final mRepo = HttpMerchantAdminRepository(m.api);
    final acct = await mRepo.me();
    expect(acct.role, MerchantRole.owner);
    await mRepo.updateStore(StoreUpdate(isOpen: true, clearPause: true));
    final menu = await mRepo.menu();
    expect(menu, isNotEmpty);

    // --- rider signup -> auto-approval -> online
    final r = Party(GoApp.rider);
    await r.login(phone(2), GoApp.rider, name: 'Live Rider');
    final rRepo = HttpRiderRepository(r.api);
    final up = HttpUploadsRepository(r.api);
    expect((await rRepo.me()).status, RiderStatus.incomplete);
    final submitted = await rRepo.submit(RiderProfileInput(
      vehicle: Vehicle(plate: 'LIV 123', makeModel: 'Honda Click', color: 'Red'),
      documents: RiderDocuments(
        licenseKey: await upload(up, UploadPurpose.riderLicense),
        orcrKey: await upload(up, UploadPurpose.riderOrcr),
        selfieKey: await upload(up, UploadPurpose.riderSelfie),
        clearanceKey: await upload(up, UploadPurpose.riderClearance),
      ),
    ));
    expect(submitted.status, RiderStatus.pendingReview);
    for (var i = 0; i < 20 && (await rRepo.me()).status != RiderStatus.approved; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    expect((await rRepo.me()).status, RiderStatus.approved);
    expect((await rRepo.setStatus(online: true, location: bongao)).isOnline, isTrue);

    // rider WebSocket: must receive offer.new
    final ws = RealWsClient(wsUrl: base!.replaceFirst('http', 'ws'), accessToken: () => r.session.accessToken, refreshToken: () async => false);
    final offerEvent = ws.events.firstWhere((e) => e is OfferNewEvent).timeout(const Duration(seconds: 20));
    await ws.connect();

    // --- customer orders food (cash)
    final c = Party(GoApp.customer);
    await c.login(phone(1), GoApp.customer, name: 'Live Customer');
    final merchants = await HttpMerchantsRepository(c.api).list(near: bongao);
    expect(merchants.items.length, 5);
    final full = await HttpMerchantsRepository(c.api).get(acct.merchant.id);
    final item = full.menu!.expand((cat) => cat.items).firstWhere((i) => i.isAvailable && i.addonGroups.every((g) => g.minSelect == 0));
    final jobs = HttpJobsRepository(c.api);
    final dropoff = Stop(address: 'Capitol', location: const LatLng(lat: 5.0362, lng: 119.7795));
    final q = await jobs.quote(QuoteRequest(
      service: ServiceType.food,
      pickup: Stop(address: full.address, location: full.location),
      dropoff: dropoff,
      food: FoodQuoteInput(merchantId: full.id, items: [FoodQuoteItem(itemId: item.id, quantity: 3, addonOptionIds: [])]),
    ));
    final key = ApiClient.newIdempotencyKey();
    final job = await jobs.create(quoteId: q.id, method: PaymentMethod.cash, notes: 'Blue gate', idempotencyKey: key);
    expect((await jobs.create(quoteId: q.id, method: PaymentMethod.cash, idempotencyKey: key)).id, job.id);
    expect(job.status, JobStatus.merchantPending);
    expect(job.dropoff.notes, 'Blue gate');

    // --- merchant accepts
    final newOrders = await mRepo.orders(MerchantOrderFilter.newOrders);
    final order = newOrders.items.firstWhere((o) => o.jobId == job.id);
    expect(order.riderPaysAtPickupCentavos, isNotNull);
    expect((await mRepo.accept(order.id, 10)).status, MerchantOrderStatus.preparing);

    // --- rider gets the offer over WS and accepts
    final offer = (await offerEvent as OfferNewEvent).offer;
    expect(offer.job.id, job.id);
    var rj = await rRepo.acceptOffer(offer.id);
    expect(riderNextStep(rj)!.target, JobStatus.arrivedPickup);
    rj = await rRepo.updateJobStatus(job.id, status: JobStatus.arrivedPickup, location: bongao);
    expect(riderNextStep(rj), isNull, reason: 'food not ready yet');
    await mRepo.markReady(order.id);
    rj = (await rRepo.activeJob())!;
    expect(rj.food!.riderPaysMerchantCentavos, isNotNull);
    rj = await rRepo.updateJobStatus(job.id, status: riderNextStep(rj)!.target, location: bongao);
    rj = await rRepo.updateJobStatus(job.id, status: riderNextStep(rj)!.target, location: bongao);
    final step = riderNextStep(rj)!;
    expect(step.needsProofPhoto, isTrue);
    rj = await rRepo.updateJobStatus(job.id, status: step.target, location: bongao, proofKey: await upload(up, UploadPurpose.proofOfDelivery));
    expect(rj.status, JobStatus.completed);

    // --- everyone sees the result
    final done = await jobs.get(job.id);
    expect(done.status, JobStatus.completed);
    expect(done.can(JobActions.rate), isTrue);
    await jobs.rate(job.id, RatingInput(riderRating: 5, riderTags: ['friendly'], merchantRating: 5));
    expect((await HttpChatRepository(c.api).messages(job.id)).items, isNotEmpty);
    final today = manilaDateString(DateTime.now());
    expect((await mRepo.sales(from: today, to: today)).ordersCount, greaterThanOrEqualTo(1));
    expect((await mRepo.payouts()).items, isNotEmpty);
    expect((await rRepo.transactions()).items.first.type, WalletTxType.commission);
    expect((await rRepo.earnings(from: today, to: today)).jobsCount, greaterThanOrEqualTo(1));
    expect((await HttpGeoRepository(c.api).search('market', bongao)), isNotEmpty);
    await ws.disconnect();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('token refresh against the real server', () async {
    final c = Party(GoApp.customer);
    await c.login(phone(3), GoApp.customer, name: 'Refresh Test');
    final before = c.session.refreshToken;
    expect(await c.api.refreshTokens(), isTrue);
    expect(c.session.refreshToken, isNot(before));
    expect((await HttpAuthRepository(c.api).me()).name, 'Refresh Test');
  }, skip: skip);
}
