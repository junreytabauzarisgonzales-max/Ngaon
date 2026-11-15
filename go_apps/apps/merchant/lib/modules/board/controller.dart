import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/merchant_session_service.dart';

class BoardController extends GetxController {
  final MerchantSessionService session = Get.find();
  final MerchantAdminRepository repo = Get.find();

  Future<void> refreshBoard() => session.loadOrders();

  Future<void> toggleOpen(bool open) async {
    if (!open && !await confirmDialog(title: 'merchant.close_store_q'.tr, message: 'merchant.close_store_body'.tr)) return;
    await session.setOpen(open);
  }

  Future<void> pause(int? minutes) => minutes == null ? session.resume() : session.pause(minutes);
}
