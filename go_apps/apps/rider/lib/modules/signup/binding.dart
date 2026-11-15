import 'package:get/get.dart';

import 'controller.dart';

class SignupBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(SignupController.new);
}
