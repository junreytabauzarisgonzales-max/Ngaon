import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/merchant_session_service.dart';

class ProfileController extends GetxController {
  final AuthService auth = Get.find();
  final AuthRepository authRepo = Get.find();
  final StorageService storage = Get.find();
  final MerchantSessionService session = Get.find();
  final language = 'en'.obs;

  @override
  void onInit() {
    super.onInit();
    language.value = storage.languageCode;
  }

  Future<void> setLanguage(String code) async {
    language.value = code;
    await setGoLanguage(code);
    await GoErrors.guard(() => authRepo.updateMe(language: code == 'fil' ? AppLanguage.fil : AppLanguage.en));
  }

  void openSettings() => Get.toNamed(Routes.settings);
  void openPayouts() => Get.toNamed(Routes.payouts);

  Future<void> logout() async {
    if (await confirmDialog(title: 'common.logout_confirm'.tr)) await auth.logout();
  }
}
