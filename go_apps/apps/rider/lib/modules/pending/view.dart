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
                if (!rejected && !suspended && p != null && p.kycRequired && !p.kycApproved)
                  _KycCard(status: p.kycStatus!, controller: controller)
                else if (!rejected && !suspended)
                  const LinearProgressIndicator(),
              ],
            );
          }),
        ],
      ),
    ),
  );
}

/// Identity verification step (Didit): ID document + selfie liveness.
class _KycCard extends StatelessWidget {
  const _KycCard({required this.status, required this.controller});
  final String status;
  final PendingController controller;

  @override
  Widget build(BuildContext context) {
    final inReview = status == 'in_review';
    final retry = status == 'expired' || status == 'declined';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(inReview ? Icons.hourglass_top : Icons.verified_user_outlined, color: GoColors.primary, size: 28),
                const SizedBox(width: 10),
                Expanded(child: Text('rider.kyc.title'.tr, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              ],
            ),
            const SizedBox(height: 6),
            Text('rider.kyc.status.$status'.tr, style: TextStyle(color: GoColors.muted)),
            if (!inReview) ...[
              const SizedBox(height: 12),
              Obx(
                () => FilledButton.icon(
                  key: const Key('kyc.start'),
                  onPressed: controller.startingKyc.value ? null : controller.verifyIdentity,
                  icon: const Icon(Icons.badge_outlined),
                  label: Text(retry || status == 'in_progress' ? 'rider.kyc.continue'.tr : 'rider.kyc.start'.tr),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
