import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/active_jobs_service.dart';
import '../shell/controller.dart';

class HomeController extends GetxController {
  final AuthService auth = Get.find();
  final ActiveJobsService activeJobs = Get.find();
  final JobsRepository jobs = Get.find();
  final recent = <Job>[].obs;
  final loadingRecent = true.obs;
  final scroll = ScrollController();

  @override
  void onInit() {
    super.onInit();
    refreshAll();
  }

  Future<void> refreshAll() async {
    await activeJobs.refresh();
    try {
      recent.assignAll((await jobs.list(JobListFilter.past)).items.take(10));
    } catch (_) {
    } finally {
      loadingRecent.value = false;
    }
  }

  /// "Good morning / afternoon / evening" in Manila time.
  String get greetingKey {
    final h = manilaNow().hour;
    return h < 12 ? 'home.greeting_morning' : (h < 18 ? 'home.greeting_afternoon' : 'home.greeting_evening');
  }

  void scrollToTop() {
    if (scroll.hasClients) scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  void open(ServiceType s) => Get.toNamed(switch (s) {
    ServiceType.ride => Routes.ride,
    ServiceType.food => Routes.food,
    ServiceType.pabili => Routes.pabili,
    ServiceType.padala => Routes.padala,
  });

  void openSearch() => Get.toNamed(Routes.food, arguments: const {'search': true});
  void openProfile() => Get.toNamed(Routes.profile);
  void openActivity() => Get.find<ShellController>().index.value = 2;

  void track(Job j) => Get.toNamed(Routes.tracking, arguments: j.id);

  @override
  void onClose() {
    scroll.dispose();
    super.onClose();
  }
}
