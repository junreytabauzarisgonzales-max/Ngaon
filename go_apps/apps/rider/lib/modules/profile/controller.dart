import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/rider_session_service.dart';

class ProfileController extends GetxController {
  final AuthService auth = Get.find();
  final AuthRepository authRepo = Get.find();
  final StorageService storage = Get.find();
  final RiderSessionService session = Get.find();
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

  Future<void> logout() async {
    if (session.online) await session.setOnline(false);
    if (await confirmDialog(title: 'common.logout_confirm'.tr)) await auth.logout();
  }
}
