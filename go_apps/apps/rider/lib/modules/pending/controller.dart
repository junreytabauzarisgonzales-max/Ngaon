import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/rider_session_service.dart';

/// Waits for approval (listens to `rider.profile_updated`).
class PendingController extends GetxController {
  final RiderSessionService session = Get.find();
  final AuthService auth = Get.find();
  Worker? _w;

  @override
  void onInit() {
    super.onInit();
    _w = ever<RiderProfile?>(session.profile, (p) {
      if (p?.status == RiderStatus.approved) Get.offAllNamed(Routes.home);
    });
  }

  Future<void> refreshStatus() => GoErrors.guard(session.loadProfile);

  void fix() => Get.offAllNamed(Routes.signup);

  @override
  void onClose() {
    _w?.dispose();
    super.onClose();
  }
}
