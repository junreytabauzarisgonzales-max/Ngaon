import 'package:get/get.dart';

import '../board/controller.dart';
import '../menu/controller.dart';
import '../profile/controller.dart';
import '../sales/controller.dart';
import 'controller.dart';

class ShellBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(ShellController.new);
    Get.lazyPut(BoardController.new);
    Get.lazyPut(MerchantMenuController.new);
    Get.lazyPut(SalesController.new);
    Get.lazyPut(ProfileController.new);
  }
}
