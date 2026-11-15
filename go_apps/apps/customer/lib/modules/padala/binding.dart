import 'package:get/get.dart';

import 'controller.dart';

class PadalaBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(PadalaController.new);
}
