import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/rider_session_service.dart';
import '../shell/controller.dart';

class HomeController extends GetxController {
  final RiderSessionService session = Get.find();
  final RiderRepository repo = Get.find();
  final LocationService location = Get.find();
  final today = Rxn<Earnings>();
  final blockers = <OnlineBlocker>[].obs;

  @override
  void onInit() {
    super.onInit();
    refreshAll();
  }

  Future<void> refreshAll() async {
    await session.refreshAll();
    final d = manilaDateString(DateTime.now());
    try {
      today.value = await repo.earnings(from: d, to: d);
    } catch (_) {}
  }

  Future<void> toggle(bool value) async {
    blockers.assignAll(await session.setOnline(value));
  }

  void openJob() => Get.toNamed(Routes.activeJob);
  void topUp() => Get.find<ShellController>().index.value = 2;
  void openSettings() => location.openSettings();
}
