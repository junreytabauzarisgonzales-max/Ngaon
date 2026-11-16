import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/active_jobs_service.dart';
import '../checkout/controller.dart';

class TrackingController extends GetxController with WidgetsBindingObserver {
  final JobsRepository repo = Get.find();
  final GoWsClient ws = Get.find();
  final LocationService location = Get.find();
  final ActiveJobsService activeJobs = Get.find();

  late final String jobId;
  final job = Rxn<Job>();
  final riderLocation = Rxn<LatLng>();
  final loading = true.obs;
  final error = Rxn<Object>();
  final busy = false.obs;
  StreamSubscription<WsEvent>? _sub;
  StreamSubscription<void>? _re;
  Timer? _poll;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    jobId = Get.arguments as String;
    _sub = ws.events.listen(_onEvent);
    _re = ws.reconnected.listen((_) {
      _subscribe();
      load();
    });
    _subscribe();
    load();
  }

  void _subscribe() => ws.send(WsTypes.jobSubscribe, {'job_id': jobId});

  void _onEvent(WsEvent e) {
    if (e is JobUpdatedEvent && e.job.id == jobId) _set(e.job);
    if (e is RiderLocationEvent && e.jobId == jobId) riderLocation.value = e.location;
  }

  void _set(Job j) {
    job.value = j;
    if (j.rider?.location != null && riderLocation.value == null) riderLocation.value = j.rider!.location;
    activeJobs.upsert(j);
    _managePolling(j);
  }

  /// Back from the payment page (or app switch): refresh right away; the
  /// backend checks PayMongo when the job is fetched.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load(silent: true);
  }

  /// Online payments: poll until paid/failed (in case the socket missed it).
  void _managePolling(Job j) {
    final waiting = j.status == JobStatus.pendingPayment && j.payment.status == PaymentStatus.pending;
    if (waiting && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => load(silent: true));
    } else if (!waiting) {
      _poll?.cancel();
      _poll = null;
    }
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) loading.value = job.value == null;
    error.value = null;
    try {
      _set(await repo.get(jobId));
    } catch (e) {
      if (!silent) error.value = e;
    } finally {
      loading.value = false;
    }
  }

  /// Rough ETA from the live rider position to the next stop (~22 km/h).
  String? get eta {
    final j = job.value, r = riderLocation.value;
    if (j == null || r == null || j.status.isFinal) return null;
    final toPickup = {JobStatus.riderAssigned}.contains(j.status);
    final toDrop = {JobStatus.pickedUp}.contains(j.status);
    if (!toPickup && !toDrop) return null;
    final target = toPickup ? j.pickup.location : j.dropoff.location;
    return formatDuration(max(60, (r.distanceTo(target) * 1.3 / 1000 / 22 * 3600).round()));
  }

  int max(int a, int b) => a > b ? a : b;

  Future<void> _act(Future<Job?> Function() fn) async {
    busy.value = true;
    try {
      final j = await fn();
      if (j != null) _set(j);
    } catch (e) {
      GoErrors.show(e);
    } finally {
      busy.value = false;
    }
  }

  Future<void> cancel() async {
    final reasons = ['tracking.reason.changed_mind', 'tracking.reason.too_long', 'tracking.reason.wrong_address', 'tracking.reason.other'];
    final reason = await showGoOptions<String>(
      title: 'tracking.cancel_why'.tr,
      options: [for (final r in reasons) GoOption(value: r.tr, label: r.tr, icon: Icons.chat_bubble_outline)],
    );
    if (reason == null) return;
    await _act(() => repo.cancel(jobId, reason));
  }

  void openChat() => Get.toNamed(
    CoreRoutes.chat,
    arguments: ChatArgs(jobId: jobId, title: job.value?.rider?.name ?? 'chat.title'.tr),
  );

  Future<void> call() async {
    final n = await GoErrors.guard(() => repo.call(jobId));
    if (n != null) await dialNumber(n);
  }

  Future<void> sos() async {
    final ok = await confirmDialog(
      title: 'tracking.sos_title'.tr,
      message: 'tracking.sos_body'.tr,
      confirmText: 'tracking.sos_send'.tr,
      danger: true,
    );
    if (!ok) return;
    final here = await location.current();
    final done = await GoErrors.guard(() async {
      await repo.sos(jobId, here);
      return true;
    });
    if (done == true) {
      await Get.dialog<void>(
        AlertDialog(
          title: Text('tracking.sos_sent'.tr),
          content: Text('tracking.sos_sent_body'.tr),
          actions: [
            TextButton(onPressed: () => dialNumber('911'), child: const Text('911')),
            TextButton(onPressed: Get.back, child: Text('common.close'.tr)),
          ],
        ),
      );
    }
  }

  Future<void> share() async {
    final link = await GoErrors.guard(() => repo.share(jobId));
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: 'tracking.share_text'.trParams({'url': link.url})));
    GoErrors.toast('common.copied'.tr);
  }

  Future<void> confirmItems(bool approved) async {
    if (!approved && !await confirmDialog(title: 'tracking.dispute_title'.tr, message: 'tracking.dispute_body'.tr, danger: true)) return;
    await _act(() => repo.confirmItems(jobId, approved));
  }

  Future<void> retryPayment() async {
    final url = job.value?.payment.checkoutUrl;
    if (url != null) await openPayment(url);
    _managePolling(job.value!);
  }

  void rate() => Get.toNamed(Routes.rate, arguments: job.value);

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    ws.send(WsTypes.jobUnsubscribe, {'job_id': jobId});
    _sub?.cancel();
    _re?.cancel();
    _poll?.cancel();
    super.onClose();
  }
}

/// Size hint for the map pane.
double mapHeight(BuildContext context) => MediaQuery.sizeOf(context).height * 0.36;
