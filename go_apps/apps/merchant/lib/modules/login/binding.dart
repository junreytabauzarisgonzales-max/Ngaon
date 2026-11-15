import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../splash/controller.dart';

class MerchantLoginBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(() => LoginController(onLoggedIn: (_) => routeMerchant()), fenix: true);
}
