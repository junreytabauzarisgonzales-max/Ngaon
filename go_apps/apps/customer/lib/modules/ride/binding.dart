import 'package:get/get.dart';

import 'controller.dart';

class RideBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(RideController.new);
}
