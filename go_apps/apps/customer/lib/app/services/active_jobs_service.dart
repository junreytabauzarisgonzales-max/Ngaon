import 'dart:async';

import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

/// Keeps the customer's active jobs fresh (home banner, orders tab).
class ActiveJobsService extends GetxService {
  final JobsRepository _jobs = Get.find();
  final GoWsClient _ws = Get.find();
  final AuthService _auth = Get.find();

  final active = <Job>[].obs;
  final revision = 0.obs;
  StreamSubscription<WsEvent>? _sub;
  StreamSubscription<void>? _re;
  StreamSubscription<PushMessage>? _push;

  @override
  void onInit() {
    super.onInit();
    _sub = _ws.events.listen((e) {
      if (e is JobUpdatedEvent) upsert(e.job);
    });
    // After a reconnect, refetch active state over REST (Section 7.6).
    _re = _ws.reconnected.listen((_) => refresh());
    // Push carries only type + IDs: always refetch over REST.
    _push = Get.find<PushService>().messages.stream.listen((m) {
      if (m.jobId != null) refresh();
    });
    _auth.onLogin.add(refresh);
    _auth.onLogout.add(() async => active.clear());
  }

  Future<void> refresh() async {
    try {
      active.assignAll((await _jobs.list(JobListFilter.active)).items);
    } catch (_) {}
  }

  void upsert(Job job) {
    final i = active.indexWhere((j) => j.id == job.id);
    if (job.status.isFinal) {
      if (i >= 0) active.removeAt(i);
    } else if (i >= 0) {
      active[i] = job;
    } else {
      active.insert(0, job);
    }
    revision.value++;
  }

  @override
  void onClose() {
    _sub?.cancel();
    _re?.cancel();
    _push?.cancel();
    super.onClose();
  }
}
