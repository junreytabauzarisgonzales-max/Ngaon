import 'package:get/get.dart';

import 'controller.dart';

class PendingBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(PendingController());
  }
}
