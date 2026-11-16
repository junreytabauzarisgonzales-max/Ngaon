import 'dart:async';
import 'dart:typed_data';

import 'package:get/get.dart';

import '../../config/app_config.dart';
import '../../models/enums.dart';
import '../../models/geo.dart';
import '../../models/job.dart';
import '../../models/merchant.dart';
import '../../models/merchant_admin.dart';
import '../../models/misc.dart';
import '../../models/rider.dart';
import '../../models/user.dart';
import '../../network/ws_client.dart';
import '../../network/ws_events.dart';
import '../repositories.dart';
import 'mock_backend.dart';

Page<T> _page<T>((List<JsonMap>, String?) r, T Function(JsonMap) parse) => Page(r.$1.map(parse).toList(), r.$2);

class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this.b);
  final MockBackend b;

  @override
  Future<OtpRequestResult> requestOtp(String phoneE164) => b.call(() => OtpRequestResult.fromJson(b.requestOtp(phoneE164)));
  @override
  Future<AuthResult> verifyOtp(String phoneE164, String code, GoApp app) =>
      b.call(() => AuthResult.fromJson(b.verifyOtp(phoneE164, code, app)));
  @override
  Future<void> logout(String refreshToken) => b.call(b.logout);
  @override
  Future<User> me() => b.call(() => User.fromJson(b.getMe()));
  @override
  Future<User> updateMe({String? name, String? email, AppLanguage? language}) =>
      b.call(() => User.fromJson(b.updateMe({'name': ?name, 'email': ?email, 'language': ?language?.name})));
  @override
  Future<void> deleteMe() => b.call(b.logout);
  @override
  Future<void> registerDevice(String fcmToken, GoApp app) => b.call(() {});
}

class MockGeoRepository implements GeoRepository {
  MockGeoRepository(this.b);
  final MockBackend b;

  @override
  Future<List<SavedPlace>> savedPlaces() => b.call(() => b.getPlaces().map(SavedPlace.fromJson).toList());
  @override
  Future<SavedPlace> addPlace(String label, String address, LatLng location) =>
      b.call(() => SavedPlace.fromJson(b.addPlace(label, address, location.toJson())));
  @override
  Future<void> deletePlace(String id) => b.call(() => b.deletePlace(id));
  @override
  Future<String> reverse(LatLng p) => b.call(() => b.reverse(p)['address'] as String);
  @override
  Future<List<GeoSearchResult>> search(String q, LatLng near) => b.call(() => b.search(q, near).map(GeoSearchResult.fromJson).toList());
  @override
  Future<ServiceArea> serviceArea() => b.call(() => ServiceArea.fromJson(MockBackend.copy(b.serviceArea)));
}

class MockMerchantsRepository implements MerchantsRepository {
  MockMerchantsRepository(this.b);
  final MockBackend b;

  @override
  Future<Page<Merchant>> list({required LatLng near, String? q, String? cursor}) =>
      b.call(() => _page(b.listMerchants(near, q, cursor), Merchant.fromJson));
  @override
  Future<Merchant> get(String id) => b.call(() => Merchant.fromJson(b.getMerchant(id)));
}

class MockJobsRepository implements JobsRepository {
  MockJobsRepository(this.b);
  final MockBackend b;

  @override
  Future<Quote> quote(QuoteRequest req) => b.call(() => Quote.fromJson(b.quote(req.toJson())));
  @override
  Future<Job> create({required String quoteId, required PaymentMethod method, String? notes, required String idempotencyKey}) =>
      b.call(() => Job.fromJson(b.createJob(quoteId, method.name, notes, idempotencyKey)));
  @override
  Future<Page<Job>> list(JobListFilter status, {String? cursor}) => b.call(() => _page(b.listJobs(status.name, cursor), Job.fromJson));
  @override
  Future<Job> get(String id) => b.call(() => Job.fromJson(b.getJob(id)));
  @override
  Future<Job> cancel(String id, String reason) => b.call(() => Job.fromJson(b.cancelJob(id, reason)));
  @override
  Future<Job> confirmItems(String id, bool approved) => b.call(() => Job.fromJson(b.confirmItems(id, approved)));
  @override
  Future<void> rate(String id, RatingInput rating) => b.call(() => b.rate(id));
  @override
  Future<ShareLink> share(String id) => b.call(
    () =>
        ShareLink(url: 'https://go.example.com/t/${b.getJob(id)['code']}', expiresAt: DateTime.now().toUtc().add(const Duration(hours: 2))),
  );
  @override
  Future<void> sos(String id, LatLng location) => b.call(() {});
  @override
  Future<String> call(String id) => b.call(() => '+639000000000');
}

class MockChatRepository implements ChatRepository {
  MockChatRepository(this.b);
  final MockBackend b;

  @override
  Future<Page<ChatMessage>> messages(String jobId, {String? cursor}) =>
      b.call(() => _page(b.messages(jobId, cursor), ChatMessage.fromJson));
  @override
  Future<ChatMessage> send(String jobId, {String? text, String? imageKey}) =>
      b.call(() => ChatMessage.fromJson(b.sendMessage(jobId, text, imageKey)));
}

class MockUploadsRepository implements UploadsRepository {
  MockUploadsRepository(this.b);
  final MockBackend b;

  @override
  Future<UploadTicket> create(UploadPurpose purpose) => b.call(() => UploadTicket.fromJson(b.createUpload(purpose.wire)));

  @override
  Future<void> put(String uploadUrl, Uint8List bytes, {void Function(double progress)? onProgress}) async {
    for (var i = 1; i <= 5; i++) {
      await Future<void>.delayed(Duration(milliseconds: (120 * b.speed).round() + 1));
      onProgress?.call(i / 5);
    }
  }
}

class MockRiderRepository implements RiderRepository {
  MockRiderRepository(this.b);
  final MockBackend b;

  /// Mock mode has no KYC provider: verification is instantly approved.
  @override
  Future<KycSession> createKycSession() => b.call(() => KycSession(sessionId: 'mock', url: '', kycStatus: 'approved'));

  @override
  Future<RiderProfile> me() => b.call(() => RiderProfile.fromJson(b.getRiderProfile()));
  @override
  Future<RiderProfile> submit(RiderProfileInput input) => b.call(() => RiderProfile.fromJson(b.submitRiderProfile(input.toJson())));
  @override
  Future<RiderProfile> setStatus({required bool online, required LatLng location}) =>
      b.call(() => RiderProfile.fromJson(b.setRiderStatus(online)));
  @override
  Future<void> postLocation(LocationPing ping) => b.call(() => b.riderLocation(ping.toJson()));
  @override
  Future<JobOffer?> currentOffer() => b.call(() {
    final o = b.getCurrentOffer();
    return o == null ? null : JobOffer.fromJson(o);
  });
  @override
  Future<Job> acceptOffer(String offerId) => b.call(() => Job.fromJson(b.acceptOffer(offerId)));
  @override
  Future<void> declineOffer(String offerId, {String? reason}) => b.call(() => b.declineOffer(offerId));
  @override
  Future<Job?> activeJob() => b.call(() {
    final j = b.riderActiveJob();
    return j == null ? null : Job.fromJson(j);
  });
  @override
  Future<Page<Job>> jobs({String? cursor, String? from, String? to}) => b.call(() => _page(b.riderJobs(cursor), Job.fromJson));
  @override
  Future<Job> updateJobStatus(
    String jobId, {
    required JobStatus status,
    required LatLng location,
    String? proofKey,
    String? receiptKey,
    int? itemTotalCentavos,
  }) => b.call(
    () => Job.fromJson(
      b.riderUpdateStatus(jobId, {
        'status': status.wire,
        'location': location.toJson(),
        'proof_key': ?proofKey,
        'receipt_key': ?receiptKey,
        'item_total_centavos': ?itemTotalCentavos,
      }),
    ),
  );
  @override
  Future<Earnings> earnings({required String from, required String to}) => b.call(() => Earnings.fromJson(b.earnings(from, to)));
  @override
  Future<Wallet> wallet() => b.call(() => Wallet.fromJson(b.wallet()));
  @override
  Future<Page<WalletTransaction>> transactions({String? cursor}) => b.call(() => _page(b.transactions(cursor), WalletTransaction.fromJson));
  @override
  Future<TopupResult> topup(int amountCentavos, PaymentMethod method, {required String idempotencyKey}) =>
      b.call(() => TopupResult.fromJson(b.topup(amountCentavos, method.name, idempotencyKey)));
}

class MockMerchantAdminRepository implements MerchantAdminRepository {
  MockMerchantAdminRepository(this.b);
  final MockBackend b;

  static String _status(MerchantOrderFilter f) => switch (f) {
    MerchantOrderFilter.newOrders => 'new',
    MerchantOrderFilter.preparing => 'preparing',
    MerchantOrderFilter.ready => 'ready',
    MerchantOrderFilter.done => 'done',
  };

  @override
  Future<MerchantAccount> me() => b.call(() => MerchantAccount.fromJson(b.merchantMe()));
  @override
  Future<Merchant> updateStore(StoreUpdate update) => b.call(() => Merchant.fromJson(b.updateStore(update.toJson())));
  @override
  Future<Page<MerchantOrder>> orders(MerchantOrderFilter status, {String? from, String? to, String? cursor}) =>
      b.call(() => _page(b.listOrders(_status(status), from, to, cursor), MerchantOrder.fromJson));
  @override
  Future<MerchantOrder> order(String id) => b.call(() => MerchantOrder.fromJson(b.getOrder(id)));
  @override
  Future<MerchantOrder> accept(String id, int prepTimeMinutes) => b.call(() => MerchantOrder.fromJson(b.acceptOrder(id, prepTimeMinutes)));
  @override
  Future<MerchantOrder> reject(String id, RejectReason reason, {String? note}) =>
      b.call(() => MerchantOrder.fromJson(b.rejectOrder(id, reason.wire)));
  @override
  Future<MerchantOrder> markReady(String id) => b.call(() => MerchantOrder.fromJson(b.markReady(id)));
  @override
  Future<List<MenuCategory>> menu() => b.call(() => b.merchantMenu().map(MenuCategory.fromJson).toList());
  @override
  Future<MenuCategory> addCategory(String name) => b.call(() => MenuCategory.fromJson(b.addCategory(name)));
  @override
  Future<MenuCategory> renameCategory(String id, String name) => b.call(() => MenuCategory.fromJson(b.renameCategory(id, name)));
  @override
  Future<void> deleteCategory(String id) => b.call(() => b.deleteCategory(id));
  @override
  Future<void> reorderCategories(List<String> ids) => b.call(() => b.reorderCategories(ids));
  @override
  Future<MenuItem> createItem(MenuItemInput input) => b.call(() => MenuItem.fromJson(b.createItem(input.toJson())));
  @override
  Future<MenuItem> updateItem(String id, MenuItemInput input) => b.call(() => MenuItem.fromJson(b.updateItem(id, input.toJson())));
  @override
  Future<void> deleteItem(String id) => b.call(() => b.deleteItem(id));
  @override
  Future<MenuItem> setItemAvailability(String id, bool available) => b.call(() => MenuItem.fromJson(b.setItemAvailability(id, available)));
  @override
  Future<void> setOptionAvailability(String id, bool available) => b.call(() => b.setOptionAvailability(id, available));
  @override
  Future<SalesReport> sales({required String from, required String to}) => b.call(() => SalesReport.fromJson(b.sales(from, to)));
  @override
  Future<Page<Payout>> payouts({String? cursor}) => b.call(() => _page(b.listPayouts(cursor), Payout.fromJson));
}

/// WebSocket stand-in fed by the [MockBackend] simulator.
class MockWsClient extends GoWsClient {
  MockWsClient(this.b);
  final MockBackend b;
  StreamSubscription<JsonMap>? _sub;
  final _events = StreamController<WsEvent>.broadcast();
  final _reconnected = StreamController<void>.broadcast();
  @override
  final state = WsState.disconnected.obs;

  @override
  Stream<WsEvent> get events => _events.stream;
  @override
  Stream<void> get reconnected => _reconnected.stream;

  @override
  Future<void> connect() async {
    if (state.value == WsState.connected) return;
    _sub ??= b.outgoing.listen((m) => _events.add(WsEvent.parse(m)));
    state.value = WsState.connected;
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    state.value = WsState.disconnected;
  }

  /// Simulates a dropped connection followed by a reconnect (for tests/demo).
  void simulateReconnect() => _reconnected.add(null);

  @override
  bool send(String type, Map<String, dynamic> data) {
    if (!isConnected) return false;
    switch (type) {
      case WsTypes.ping:
        b.emit(WsTypes.pong, const {});
      case WsTypes.jobSubscribe:
        b.subscribedJobs.add('${data['job_id']}');
      case WsTypes.jobUnsubscribe:
        b.subscribedJobs.remove('${data['job_id']}');
      case WsTypes.riderLocation:
        b.riderLocation(data);
    }
    return true;
  }
}
