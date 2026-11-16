import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/rider_session_service.dart';

class WalletController extends GetxController with WidgetsBindingObserver {
  final RiderRepository repo = Get.find();
  final RiderSessionService session = Get.find();
  final wallet = Rxn<Wallet>();
  final txs = <WalletTransaction>[].obs;
  final loading = false.obs;
  final error = Rxn<Object>();
  final topupBusy = false.obs;
  String? _cursor;
  bool hasMore = false;

  /// Set while a top-up is being paid in the browser.
  final awaitingTopup = false.obs;
  Timer? _topupPoll;
  int? _balanceBefore;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
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
      _balanceBefore = wallet.value?.balanceCentavos;
      if (AppConfig.current.useMockApi) {
        GoErrors.toast('rider.topup_mock'.tr);
      } else {
        await openCheckoutPage(r.checkoutUrl);
      }
      Get.back();
      _watchTopup();
    } catch (e) {
      GoErrors.show(e);
    } finally {
      topupBusy.value = false;
    }
  }

  /// The backend confirms PayMongo top-ups when the wallet is fetched, so poll
  /// for a few minutes after the checkout opens (stops once the balance rises).
  void _watchTopup() {
    _topupPoll?.cancel();
    awaitingTopup.value = true;
    var ticks = 0;
    _topupPoll = Timer.periodic(const Duration(seconds: 5), (t) async {
      ticks++;
      await load();
      final now = wallet.value?.balanceCentavos;
      if ((now != null && _balanceBefore != null && now > _balanceBefore!) || ticks >= 36) {
        t.cancel();
        awaitingTopup.value = false;
        if (ticks < 36) GoErrors.toast('rider.topup_received'.tr);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the payment page: check right away.
    if (state == AppLifecycleState.resumed && awaitingTopup.value) load();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _topupPoll?.cancel();
    super.onClose();
  }
}
