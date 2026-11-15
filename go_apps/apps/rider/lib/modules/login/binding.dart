import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/rider_session_service.dart';

/// Shared OTP flow; then route by rider_profile.status.
class RiderLoginBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(
    () => LoginController(
      onLoggedIn: (_) async {
        final p = await Get.find<RiderSessionService>().loadProfile();
        Get.offAllNamed(RiderSessionService.routeFor(p));
      },
    ),
    fenix: true,
  );
}
