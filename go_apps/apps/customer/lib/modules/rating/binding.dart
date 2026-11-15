import 'package:get/get.dart';

import 'controller.dart';

class RatingBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(RatingController.new);
}
