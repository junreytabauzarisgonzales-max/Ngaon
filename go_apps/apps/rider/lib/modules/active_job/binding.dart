import 'package:get/get.dart';

import 'controller.dart';

class ActiveJobBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(ActiveJobController.new);
}
