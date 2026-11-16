import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../config/app_config.dart';
import '../../models/enums.dart';
import '../../models/geo.dart';
import '../../models/job.dart';
import '../../models/merchant.dart';
import '../../models/merchant_admin.dart';
import '../../models/misc.dart';
import '../../models/rider.dart';
import '../../models/user.dart';
import '../../network/api_client.dart';
import '../../network/api_exception.dart';
import '../repositories.dart';

class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(this.api);
  final ApiClient api;

  @override
  Future<OtpRequestResult> requestOtp(String phoneE164) =>
      api.send('POST', '/auth/otp/request', (d) => OtpRequestResult.fromJson(asMap(d)), body: {'phone': phoneE164});

  @override
  Future<AuthResult> verifyOtp(String phoneE164, String code, GoApp app) =>
      api.send('POST', '/auth/otp/verify', (d) => AuthResult.fromJson(asMap(d)), body: {'phone': phoneE164, 'code': code, 'app': app.name});

  @override
  Future<void> logout(String refreshToken) => api.sendVoid('POST', '/auth/logout', body: {'refresh_token': refreshToken});

  @override
  Future<User> me() => api.get('/me', (d) => User.fromJson(asMap(d)));

  @override
  Future<User> updateMe({String? name, String? email, AppLanguage? language}) =>
      api.send('PATCH', '/me', (d) => User.fromJson(asMap(d)), body: {'name': ?name, 'email': ?email, 'language': ?language?.name});

  @override
  Future<void> deleteMe() => api.sendVoid('DELETE', '/me');

  @override
  Future<void> registerDevice(String fcmToken, GoApp app) =>
      api.sendVoid('POST', '/me/devices', body: {'fcm_token': fcmToken, 'platform': 'android', 'app': app.name});
}

class HttpGeoRepository implements GeoRepository {
  HttpGeoRepository(this.api);
  final ApiClient api;

  @override
  Future<List<SavedPlace>> savedPlaces() => api.get('/me/places', (d) => asList(d, SavedPlace.fromJson));

  @override
  Future<SavedPlace> addPlace(String label, String address, LatLng location) => api.send(
    'POST',
    '/me/places',
    (d) => SavedPlace.fromJson(asMap(d)),
    body: {'label': label, 'address': address, 'location': location.toJson()},
  );

  @override
  Future<void> deletePlace(String id) => api.sendVoid('DELETE', '/me/places/$id');

  @override
  Future<String> reverse(LatLng p) =>
      api.get('/geo/reverse', (d) => ReverseGeocodeResult.fromJson(asMap(d)).address, query: {'lat': p.lat, 'lng': p.lng});

  @override
  Future<List<GeoSearchResult>> search(String q, LatLng near) =>
      api.get('/geo/search', (d) => asList(d, GeoSearchResult.fromJson), query: {'q': q, 'lat': near.lat, 'lng': near.lng});

  @override
  Future<ServiceArea> serviceArea() => api.get('/service-area', (d) => ServiceArea.fromJson(asMap(d)));
}

class HttpMerchantsRepository implements MerchantsRepository {
  HttpMerchantsRepository(this.api);
  final ApiClient api;

  @override
  Future<Page<Merchant>> list({required LatLng near, String? q, String? cursor}) => api.getPage(
    '/merchants',
    Merchant.fromJson,
    query: {'lat': near.lat, 'lng': near.lng, 'q': (q?.isEmpty ?? true) ? null : q, 'cursor': cursor, 'limit': 20},
  );

  @override
  Future<Merchant> get(String id) => api.get('/merchants/$id', (d) => Merchant.fromJson(asMap(d)));
}

class HttpJobsRepository implements JobsRepository {
  HttpJobsRepository(this.api);
  final ApiClient api;
  Job _job(Object? d) => Job.fromJson(asMap(d));

  @override
  Future<Quote> quote(QuoteRequest req) => api.send('POST', '/quotes', (d) => Quote.fromJson(asMap(d)), body: req.toJson());

  @override
  Future<Job> create({required String quoteId, required PaymentMethod method, String? notes, required String idempotencyKey}) => api.send(
    'POST',
    '/jobs',
    _job,
    body: {'quote_id': quoteId, 'payment_method': method.name, 'notes': ?notes},
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<Page<Job>> list(JobListFilter status, {String? cursor}) =>
      api.getPage('/jobs', Job.fromJson, query: {'status': status.name, 'cursor': cursor, 'limit': 20});

  @override
  Future<Job> get(String id) => api.get('/jobs/$id', _job);

  @override
  Future<Job> cancel(String id, String reason) => api.send('POST', '/jobs/$id/cancel', _job, body: {'reason': reason});

  @override
  Future<Job> confirmItems(String id, bool approved) => api.send('POST', '/jobs/$id/confirm-items', _job, body: {'approved': approved});

  @override
  Future<void> rate(String id, RatingInput rating) => api.sendVoid('POST', '/jobs/$id/rate', body: rating.toJson());

  @override
  Future<ShareLink> share(String id) => api.send('POST', '/jobs/$id/share', (d) => ShareLink.fromJson(asMap(d)));

  @override
  Future<void> sos(String id, LatLng location) => api.sendVoid('POST', '/jobs/$id/sos', body: {'location': location.toJson()});

  @override
  Future<String> call(String id) => api.send('POST', '/jobs/$id/call', (d) => MaskedNumber.fromJson(asMap(d)).maskedNumber);
}

class HttpChatRepository implements ChatRepository {
  HttpChatRepository(this.api);
  final ApiClient api;

  @override
  Future<Page<ChatMessage>> messages(String jobId, {String? cursor}) =>
      api.getPage('/jobs/$jobId/messages', ChatMessage.fromJson, query: {'cursor': cursor, 'limit': 50});

  @override
  Future<ChatMessage> send(String jobId, {String? text, String? imageKey}) =>
      api.send('POST', '/jobs/$jobId/messages', (d) => ChatMessage.fromJson(asMap(d)), body: {'text': ?text, 'image_key': ?imageKey});
}

class HttpUploadsRepository implements UploadsRepository {
  HttpUploadsRepository(this.api);
  final ApiClient api;

  /// Separate Dio: presigned URLs must not receive our auth header.
  final Dio _plain = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  @override
  Future<UploadTicket> create(UploadPurpose purpose) =>
      api.send('POST', '/uploads', (d) => UploadTicket.fromJson(asMap(d)), body: {'purpose': purpose.wire, 'content_type': 'image/jpeg'});

  @override
  Future<void> put(String uploadUrl, Uint8List bytes, {void Function(double progress)? onProgress}) async {
    try {
      await _plain.put<void>(
        uploadUrl,
        data: Stream.fromIterable([bytes]),
        options: Options(headers: {Headers.contentTypeHeader: 'image/jpeg', Headers.contentLengthHeader: bytes.length}),
        onSendProgress: (sent, total) => onProgress?.call(total <= 0 ? 0 : sent / total),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

class HttpRiderRepository implements RiderRepository {
  HttpRiderRepository(this.api);
  final ApiClient api;

  @override
  Future<KycSession> createKycSession() => api.send('POST', '/rider/kyc/session', (d) => KycSession.fromJson(asMap(d)));
  RiderProfile _profile(Object? d) => RiderProfile.fromJson(asMap(d));
  Job _job(Object? d) => Job.fromJson(asMap(d));

  @override
  Future<RiderProfile> me() => api.get('/rider/me', _profile);

  @override
  Future<RiderProfile> submit(RiderProfileInput input) => api.send('PUT', '/rider/me', _profile, body: input.toJson());

  @override
  Future<RiderProfile> setStatus({required bool online, required LatLng location}) =>
      api.send('POST', '/rider/status', _profile, body: {'online': online, 'location': location.toJson()});

  @override
  Future<void> postLocation(LocationPing ping) => api.sendVoid('POST', '/rider/location', body: ping.toJson());

  @override
  Future<JobOffer?> currentOffer() => api.get('/rider/offers/current', (d) => d == null ? null : JobOffer.fromJson(asMap(d)));

  @override
  Future<Job> acceptOffer(String offerId) => api.send('POST', '/rider/offers/$offerId/accept', _job);

  @override
  Future<void> declineOffer(String offerId, {String? reason}) =>
      api.sendVoid('POST', '/rider/offers/$offerId/decline', body: {'reason': ?reason});

  @override
  Future<Job?> activeJob() => api.get('/rider/jobs/active', (d) => d == null ? null : _job(d));

  @override
  Future<Page<Job>> jobs({String? cursor, String? from, String? to}) =>
      api.getPage('/rider/jobs', Job.fromJson, query: {'cursor': cursor, 'from': from, 'to': to, 'limit': 20});

  @override
  Future<Job> updateJobStatus(
    String jobId, {
    required JobStatus status,
    required LatLng location,
    String? proofKey,
    String? receiptKey,
    int? itemTotalCentavos,
  }) => api.send(
    'POST',
    '/rider/jobs/$jobId/status',
    _job,
    body: {
      'status': status.wire,
      'location': location.toJson(),
      'proof_key': ?proofKey,
      'receipt_key': ?receiptKey,
      'item_total_centavos': ?itemTotalCentavos,
    },
  );

  @override
  Future<Earnings> earnings({required String from, required String to}) =>
      api.get('/rider/earnings', (d) => Earnings.fromJson(asMap(d)), query: {'from': from, 'to': to});

  @override
  Future<Wallet> wallet() => api.get('/rider/wallet', (d) => Wallet.fromJson(asMap(d)));

  @override
  Future<Page<WalletTransaction>> transactions({String? cursor}) =>
      api.getPage('/rider/wallet/transactions', WalletTransaction.fromJson, query: {'cursor': cursor, 'limit': 20});

  @override
  Future<TopupResult> topup(int amountCentavos, PaymentMethod method, {required String idempotencyKey}) => api.send(
    'POST',
    '/rider/wallet/topups',
    (d) => TopupResult.fromJson(asMap(d)),
    body: {'amount_centavos': amountCentavos, 'method': method.name},
    idempotencyKey: idempotencyKey,
  );
}

class HttpMerchantAdminRepository implements MerchantAdminRepository {
  HttpMerchantAdminRepository(this.api);
  final ApiClient api;
  MerchantOrder _order(Object? d) => MerchantOrder.fromJson(asMap(d));
  MenuItem _item(Object? d) => MenuItem.fromJson(asMap(d));

  static String filterWire(MerchantOrderFilter f) => switch (f) {
    MerchantOrderFilter.newOrders => 'new',
    MerchantOrderFilter.preparing => 'preparing',
    MerchantOrderFilter.ready => 'ready',
    MerchantOrderFilter.done => 'done',
  };

  @override
  Future<MerchantAccount> me() => api.get('/merchant/me', (d) => MerchantAccount.fromJson(asMap(d)));

  @override
  Future<Merchant> updateStore(StoreUpdate update) =>
      api.send('PATCH', '/merchant/store', (d) => Merchant.fromJson(asMap(d)), body: update.toJson());

  @override
  Future<Page<MerchantOrder>> orders(MerchantOrderFilter status, {String? from, String? to, String? cursor}) => api.getPage(
    '/merchant/orders',
    MerchantOrder.fromJson,
    query: {'status': filterWire(status), 'from': from, 'to': to, 'cursor': cursor, 'limit': 50},
  );

  @override
  Future<MerchantOrder> order(String id) => api.get('/merchant/orders/$id', _order);

  @override
  Future<MerchantOrder> accept(String id, int prepTimeMinutes) =>
      api.send('POST', '/merchant/orders/$id/accept', _order, body: {'prep_time_minutes': prepTimeMinutes});

  @override
  Future<MerchantOrder> reject(String id, RejectReason reason, {String? note}) =>
      api.send('POST', '/merchant/orders/$id/reject', _order, body: {'reason': reason.wire, 'note': ?note});

  @override
  Future<MerchantOrder> markReady(String id) => api.send('POST', '/merchant/orders/$id/ready', _order);

  @override
  Future<List<MenuCategory>> menu() => api.get('/merchant/menu', (d) => asList(d, MenuCategory.fromJson));

  @override
  Future<MenuCategory> addCategory(String name) =>
      api.send('POST', '/merchant/menu/categories', (d) => MenuCategory.fromJson(asMap(d)), body: {'name': name});

  @override
  Future<MenuCategory> renameCategory(String id, String name) =>
      api.send('PATCH', '/merchant/menu/categories/$id', (d) => MenuCategory.fromJson(asMap(d)), body: {'name': name});

  @override
  Future<void> deleteCategory(String id) => api.sendVoid('DELETE', '/merchant/menu/categories/$id');

  @override
  Future<void> reorderCategories(List<String> ids) => api.sendVoid('PUT', '/merchant/menu/categories/order', body: {'category_ids': ids});

  @override
  Future<MenuItem> createItem(MenuItemInput input) => api.send('POST', '/merchant/menu/items', _item, body: input.toJson());

  @override
  Future<MenuItem> updateItem(String id, MenuItemInput input) => api.send('PUT', '/merchant/menu/items/$id', _item, body: input.toJson());

  @override
  Future<void> deleteItem(String id) => api.sendVoid('DELETE', '/merchant/menu/items/$id');

  @override
  Future<MenuItem> setItemAvailability(String id, bool available) =>
      api.send('PATCH', '/merchant/menu/items/$id/availability', _item, body: {'is_available': available});

  @override
  Future<void> setOptionAvailability(String id, bool available) =>
      api.sendVoid('PATCH', '/merchant/menu/addon-options/$id/availability', body: {'is_available': available});

  @override
  Future<SalesReport> sales({required String from, required String to}) =>
      api.get('/merchant/reports/sales', (d) => SalesReport.fromJson(asMap(d)), query: {'from': from, 'to': to});

  @override
  Future<Page<Payout>> payouts({String? cursor}) =>
      api.getPage('/merchant/payouts', Payout.fromJson, query: {'cursor': cursor, 'limit': 20});
}
