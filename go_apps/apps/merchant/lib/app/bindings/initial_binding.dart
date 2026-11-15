import 'package:get/get.dart';

import '../services/merchant_session_service.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(MerchantSessionService(), permanent: true);
  }
}
