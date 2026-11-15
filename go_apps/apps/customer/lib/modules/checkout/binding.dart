import 'package:get/get.dart';

import 'controller.dart';

class CheckoutBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(CheckoutController.new);
}
