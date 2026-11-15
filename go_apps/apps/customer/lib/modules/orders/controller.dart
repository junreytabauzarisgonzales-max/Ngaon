import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/active_jobs_service.dart';

class JobList {
  JobList(this.filter);
  final JobListFilter filter;
  final items = <Job>[].obs;
  final loading = false.obs;
  final error = Rxn<Object>();
  String? cursor;
  bool hasMore = false;
}

class OrdersController extends GetxController {
  final JobsRepository repo = Get.find();
  final ActiveJobsService activeJobs = Get.find();
  final active = JobList(JobListFilter.active);
  final past = JobList(JobListFilter.past);

  @override
  void onInit() {
    super.onInit();
    load(active);
    load(past);
    // Keep the active list in sync with realtime updates.
    ever(activeJobs.revision, (_) => load(active));
  }

  Future<void> load(JobList l, {bool more = false}) async {
    if (l.loading.value) return;
    l.loading.value = true;
    l.error.value = null;
    try {
      final page = await repo.list(l.filter, cursor: more ? l.cursor : null);
      if (more) {
        l.items.addAll(page.items);
      } else {
        l.items.assignAll(page.items);
      }
      l.cursor = page.nextCursor;
      l.hasMore = page.hasMore;
    } catch (e) {
      l.error.value = e;
    } finally {
      l.loading.value = false;
    }
  }

  void open(Job j) => Get.toNamed(Routes.tracking, arguments: j.id);
}
