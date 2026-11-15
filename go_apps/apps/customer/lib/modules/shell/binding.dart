import 'package:get/get.dart';

import '../home/controller.dart';
import '../messages/controller.dart';
import '../orders/controller.dart';
import '../scan/controller.dart';
import 'controller.dart';

class ShellBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(ShellController());
    Get.lazyPut(HomeController.new);
    Get.lazyPut(ScanController.new);
    Get.lazyPut(OrdersController.new);
    Get.lazyPut(MessagesController.new);
  }
}
