import 'package:get/get.dart';

import 'controller.dart';

class PabiliBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(PabiliController.new);
}
