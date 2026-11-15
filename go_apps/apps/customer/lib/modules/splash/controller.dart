import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';

class SplashController extends GetxController {
  final AuthService auth = Get.find();
  final StorageService storage = Get.find();
  final LocationService location = Get.find();
  final requesting = false.obs;

  @override
  void onReady() {
    super.onReady();
    if (Get.currentRoute == Routes.splash) route();
  }

  Future<void> route() async {
    if (!storage.onboardingDone) {
      Get.offAllNamed(Routes.onboarding);
      return;
    }
    if (auth.isLoggedIn) {
      await auth.afterRestore();
      Get.offAllNamed(Routes.home);
    } else {
      Get.offAllNamed(Routes.login);
    }
  }

  /// Plain-language permission ask, then continue either way.
  Future<void> allowLocation() async {
    requesting.value = true;
    await location.request();
    requesting.value = false;
    await storage.setOnboardingDone();
    await route();
  }

  Future<void> skip() async {
    await storage.setOnboardingDone();
    await route();
  }
}
