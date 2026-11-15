import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/rider_session_service.dart';

class WalletController extends GetxController {
  final RiderRepository repo = Get.find();
  final RiderSessionService session = Get.find();
  final wallet = Rxn<Wallet>();
  final txs = <WalletTransaction>[].obs;
  final loading = false.obs;
  final error = Rxn<Object>();
  final topupBusy = false.obs;
  String? _cursor;
  bool hasMore = false;

  @override
  void onInit() {
    super.onInit();
    load();
    // Balance changes arrive via rider.profile_updated.
    ever(session.profile, (_) => load());
  }

  Future<void> load({bool more = false}) async {
    if (loading.value) return;
    loading.value = true;
    error.value = null;
    try {
      if (!more) wallet.value = await repo.wallet();
      final page = await repo.transactions(cursor: more ? _cursor : null);
      more ? txs.addAll(page.items) : txs.assignAll(page.items);
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
    } catch (e) {
      error.value = e;
    } finally {
      loading.value = false;
    }
  }

  /// Same key reused if the user retries the same amount/method.
  String? _key;
  (int, PaymentMethod)? _keyFor;

  Future<void> topUp(int amount, PaymentMethod method) async {
    if (_keyFor != (amount, method)) {
      _key = ApiClient.newIdempotencyKey();
      _keyFor = (amount, method);
    }
    topupBusy.value = true;
    try {
      final r = await repo.topup(amount, method, idempotencyKey: _key!);
      _keyFor = null;
      if (AppConfig.current.useMockApi) {
        GoErrors.toast('rider.topup_mock'.tr);
      } else {
        await openCheckoutPage(r.checkoutUrl);
      }
      Get.back();
    } catch (e) {
      GoErrors.show(e);
    } finally {
      topupBusy.value = false;
    }
  }
}
