import 'package:get/get.dart';

import 'controller.dart';

class PayoutsBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(PayoutsController.new);
}
