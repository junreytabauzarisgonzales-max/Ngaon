import 'package:get/get.dart';

import 'controller.dart';

class OrderBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(OrderController.new);
}
