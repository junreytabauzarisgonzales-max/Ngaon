import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';

/// Shared OTP flow; after login go to Home.
class CustomerLoginBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(() => LoginController(onLoggedIn: (_) async => Get.offAllNamed(Routes.home)), fenix: true);
}
