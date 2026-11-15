import 'package:get/get.dart';

import 'cart_controller.dart';
import 'controller.dart';

class FoodBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(FoodController.new);
}

class MenuBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(MerchantMenuController.new);
}

class CartBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(CartController.new);
}
