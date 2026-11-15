import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class PendingView extends GetView<PendingController> {
  const PendingView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [IconButton(onPressed: controller.auth.logout, icon: const Icon(Icons.logout))],
    ),
    body: RefreshIndicator(
      onRefresh: controller.refreshStatus,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Obx(() {
            final p = controller.session.profile.value;
            final status = p?.status ?? RiderStatus.pendingReview;
            final rejected = status == RiderStatus.rejected;
            final suspended = status == RiderStatus.suspended;
            return Column(
              children: [
                const SizedBox(height: 40),
                Icon(
                  rejected ? Icons.cancel : (suspended ? Icons.block : Icons.hourglass_top),
                  size: 88,
                  color: rejected || suspended ? GoColors.danger : GoColors.accent,
                ),
                const SizedBox(height: 16),
                Text(
                  'rider.status.${status.wire}'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'rider.status_body.${status.wire}'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: GoColors.muted, fontSize: 15),
                ),
                if (rejected && p?.rejectionReason != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: GoColors.danger.withValues(alpha: 0.08),
                    child: Padding(padding: const EdgeInsets.all(16), child: Text(p!.rejectionReason!)),
                  ),
                ],
                const SizedBox(height: 24),
                if (rejected) FilledButton(onPressed: controller.fix, child: Text('rider.fix_resubmit'.tr)),
                if (!rejected && !suspended) const LinearProgressIndicator(),
              ],
            );
          }),
        ],
      ),
    ),
  );
}
