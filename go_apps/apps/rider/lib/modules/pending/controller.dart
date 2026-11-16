import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/rider_session_service.dart';

/// Waits for approval (listens to `rider.profile_updated`). When identity
/// verification (Didit) is enabled, guides the rider through it and polls the
/// profile — the backend checks Didit on each GET /rider/me.
class PendingController extends GetxController with WidgetsBindingObserver {
  final RiderSessionService session = Get.find();
  final RiderRepository repo = Get.find();
  final AuthService auth = Get.find();
  final startingKyc = false.obs;
  Worker? _w;
  Timer? _poll;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _w = ever<RiderProfile?>(session.profile, (p) {
      if (p?.status == RiderStatus.approved) Get.offAllNamed(Routes.home);
    });
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (session.profile.value?.status == RiderStatus.pendingReview) refreshStatus();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the verification page: check right away.
    if (state == AppLifecycleState.resumed) refreshStatus();
  }

  Future<void> refreshStatus() => GoErrors.guard(session.loadProfile);

  /// Opens Didit's hosted verification (ID + selfie liveness) in an in-app browser.
  Future<void> verifyIdentity() async {
    startingKyc.value = true;
    try {
      final s = await repo.createKycSession();
      if (s.url.isNotEmpty) await openCheckoutPage(s.url);
      await refreshStatus();
    } catch (e) {
      GoErrors.show(e);
    } finally {
      startingKyc.value = false;
    }
  }

  void fix() => Get.offAllNamed(Routes.signup);

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _w?.dispose();
    super.onClose();
  }
}
