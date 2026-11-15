import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/rider_session_service.dart';

class SplashController extends GetxController {
  final AuthService auth = Get.find();
  final RiderSessionService session = Get.find();
  final error = Rxn<Object>();

  @override
  void onReady() {
    super.onReady();
    route();
  }

  Future<void> route() async {
    error.value = null;
    if (!auth.isLoggedIn) {
      Get.offAllNamed(Routes.login);
      return;
    }
    try {
      await auth.afterRestore();
      final p = await session.loadProfile();
      await session.refreshAll();
      Get.offAllNamed(RiderSessionService.routeFor(p));
    } catch (e) {
      error.value = e;
    }
  }
}
