import 'package:get/get.dart';

import '../earnings/controller.dart';
import '../home/controller.dart';
import '../profile/controller.dart';
import '../wallet/controller.dart';
import 'controller.dart';

class ShellBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(ShellController.new);
    Get.lazyPut(HomeController.new);
    Get.lazyPut(EarningsController.new);
    Get.lazyPut(WalletController.new);
    Get.lazyPut(ProfileController.new);
  }
}
