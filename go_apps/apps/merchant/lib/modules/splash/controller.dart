import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/merchant_session_service.dart';

/// Routes after login: GET /merchant/me; `forbidden` -> not a merchant.
Future<void> routeMerchant() async {
  final session = Get.find<MerchantSessionService>();
  try {
    await session.loadAccount();
    await session.loadOrders();
    Get.offAllNamed(Routes.home);
  } on ApiException catch (e) {
    if (e.code == ErrorCodes.forbidden) {
      Get.offAllNamed(Routes.notMerchant);
      return;
    }
    rethrow;
  }
}

class SplashController extends GetxController {
  final AuthService auth = Get.find();
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
      await routeMerchant();
    } catch (e) {
      error.value = e;
    }
  }
}
