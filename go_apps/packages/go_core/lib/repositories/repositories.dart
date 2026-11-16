import 'dart:typed_data';

import '../config/app_config.dart';
import '../models/enums.dart';
import '../models/geo.dart';
import '../models/job.dart';
import '../models/merchant.dart';
import '../models/merchant_admin.dart';
import '../models/misc.dart';
import '../models/rider.dart';
import '../models/user.dart';

/// Repository interfaces. Controllers only depend on these (never on Dio).
/// Each maps 1:1 onto endpoints in API_CONTRACT.md.

abstract class AuthRepository {
  Future<OtpRequestResult> requestOtp(String phoneE164);
  Future<AuthResult> verifyOtp(String phoneE164, String code, GoApp app);
  Future<void> logout(String refreshToken);
  Future<User> me();
  Future<User> updateMe({String? name, String? email, AppLanguage? language});
  Future<void> deleteMe();
  Future<void> registerDevice(String fcmToken, GoApp app);
}

abstract class GeoRepository {
  Future<List<SavedPlace>> savedPlaces();
  Future<SavedPlace> addPlace(String label, String address, LatLng location);
  Future<void> deletePlace(String id);
  Future<String> reverse(LatLng p);
  Future<List<GeoSearchResult>> search(String q, LatLng near);
  Future<ServiceArea> serviceArea();
}

abstract class MerchantsRepository {
  Future<Page<Merchant>> list({required LatLng near, String? q, String? cursor});
  Future<Merchant> get(String id);
}

enum JobListFilter { active, past }

abstract class JobsRepository {
  Future<Quote> quote(QuoteRequest req);
  Future<Job> create({required String quoteId, required PaymentMethod method, String? notes, required String idempotencyKey});
  Future<Page<Job>> list(JobListFilter status, {String? cursor});
  Future<Job> get(String id);
  Future<Job> cancel(String id, String reason);
  Future<Job> confirmItems(String id, bool approved);
  Future<void> rate(String id, RatingInput rating);
  Future<ShareLink> share(String id);
  Future<void> sos(String id, LatLng location);
  Future<String> call(String id);
}

abstract class ChatRepository {
  Future<Page<ChatMessage>> messages(String jobId, {String? cursor});
  Future<ChatMessage> send(String jobId, {String? text, String? imageKey});
}

abstract class UploadsRepository {
  Future<UploadTicket> create(UploadPurpose purpose);

  /// PUTs bytes to the presigned URL with no auth header.
  Future<void> put(String uploadUrl, Uint8List bytes, {void Function(double progress)? onProgress});
}

abstract class RiderRepository {
  Future<RiderProfile> me();
  Future<RiderProfile> submit(RiderProfileInput input);
  Future<RiderProfile> setStatus({required bool online, required LatLng location});
  Future<void> postLocation(LocationPing ping);
  Future<JobOffer?> currentOffer();
  Future<Job> acceptOffer(String offerId);
  Future<void> declineOffer(String offerId, {String? reason});
  Future<Job?> activeJob();
  Future<Page<Job>> jobs({String? cursor, String? from, String? to});
  Future<Job> updateJobStatus(
    String jobId, {
    required JobStatus status,
    required LatLng location,
    String? proofKey,
    String? receiptKey,
    int? itemTotalCentavos,
  });
  Future<Earnings> earnings({required String from, required String to});
  Future<Wallet> wallet();
  Future<Page<WalletTransaction>> transactions({String? cursor});
  Future<TopupResult> topup(int amountCentavos, PaymentMethod method, {required String idempotencyKey});

  /// ADDED: start/resume Didit identity verification; returns the hosted URL.
  Future<KycSession> createKycSession();
}

enum MerchantOrderFilter { newOrders, preparing, ready, done }

abstract class MerchantAdminRepository {
  Future<MerchantAccount> me();
  Future<Merchant> updateStore(StoreUpdate update);
  Future<Page<MerchantOrder>> orders(MerchantOrderFilter status, {String? from, String? to, String? cursor});
  Future<MerchantOrder> order(String id);
  Future<MerchantOrder> accept(String id, int prepTimeMinutes);
  Future<MerchantOrder> reject(String id, RejectReason reason, {String? note});
  Future<MerchantOrder> markReady(String id);
  Future<List<MenuCategory>> menu();
  Future<MenuCategory> addCategory(String name);
  Future<MenuCategory> renameCategory(String id, String name);
  Future<void> deleteCategory(String id);
  Future<void> reorderCategories(List<String> ids);
  Future<MenuItem> createItem(MenuItemInput input);
  Future<MenuItem> updateItem(String id, MenuItemInput input);
  Future<void> deleteItem(String id);
  Future<MenuItem> setItemAvailability(String id, bool available);
  Future<void> setOptionAvailability(String id, bool available);
  Future<SalesReport> sales({required String from, required String to});
  Future<Page<Payout>> payouts({String? cursor});
}
