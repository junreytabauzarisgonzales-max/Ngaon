import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/active_jobs_service.dart';

/// Conversations = jobs that have (or had) a rider.
class MessagesController extends GetxController {
  final JobsRepository repo = Get.find();
  final ActiveJobsService activeJobs = Get.find();
  final past = <Job>[].obs;
  final loading = false.obs;
  final liveCount = 0.obs;

  List<Job> get live => activeJobs.active.where((j) => j.rider != null).toList();

  @override
  void onInit() {
    super.onInit();
    ever(activeJobs.revision, (_) => _count());
    ever(activeJobs.active, (_) => _count());
    _count();
    load();
  }

  void _count() => liveCount.value = live.where((j) => j.can(JobActions.chat)).length;

  Future<void> load() async {
    loading.value = true;
    try {
      await activeJobs.refresh();
      past.assignAll((await repo.list(JobListFilter.past)).items.where((j) => j.rider != null));
    } catch (_) {
    } finally {
      loading.value = false;
    }
  }

  void open(Job j) => Get.toNamed(
    CoreRoutes.chat,
    arguments: ChatArgs(jobId: j.id, title: j.rider?.name ?? 'chat.title'.tr, readOnly: !j.can(JobActions.chat)),
  );
}
