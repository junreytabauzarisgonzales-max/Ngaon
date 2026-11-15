import 'package:get/get.dart';

import 'item_editor_controller.dart';

class ItemEditorBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(ItemEditorController.new);
}
