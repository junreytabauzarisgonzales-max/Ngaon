import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class TrackingView extends GetView<TrackingController> {
  const TrackingView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Obx(() => Text(c.job.value?.code ?? ''))),
      body: Obx(() {
        if (c.loading.value) return const LoadingState();
        final j = c.job.value;
        if (j == null) return ErrorState(error: c.error.value ?? 'x', onRetry: c.load);
        final rider = c.riderLocation.value;
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            if (!j.status.isFinal)
              SizedBox(
                height: mapHeight(context),
                child: GoMap(
                  center: rider ?? j.pickup.location,
                  followMarkerId: rider == null ? null : 'rider',
                  markers: [
                    GoMarker('p', j.pickup.location, j.service == ServiceType.food ? MarkerKind.store : MarkerKind.pickup),
                    GoMarker('d', j.dropoff.location, MarkerKind.dropoff),
                    if (rider != null) GoMarker('rider', rider, MarkerKind.rider),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(job: j, eta: c.eta),
                  if (j.status == JobStatus.pendingPayment) _PaymentCard(job: j, onRetry: c.retryPayment),
                  if (j.can(JobActions.confirmItems)) _ReceiptCard(job: j, busy: c.busy.value, onConfirm: c.confirmItems),
                  if (j.rider != null && !j.status.isFinal) ...[
                    const SizedBox(height: 12),
                    RiderCard(
                      rider: j.rider!,
                      onCall: j.can(JobActions.call) ? c.call : null,
                      onChat: j.can(JobActions.chat) ? c.openChat : null,
                    ),
                  ],
                  if (j.service == ServiceType.ride && (j.can(JobActions.sos) || j.can(JobActions.share))) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (j.can(JobActions.share))
                          Expanded(
                            child: OutlinedButton.icon(onPressed: c.share, icon: const Icon(Icons.share), label: Text('tracking.share'.tr)),
                          ),
                        const SizedBox(width: 12),
                        if (j.can(JobActions.sos))
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: GoColors.danger, minimumSize: const Size.fromHeight(50)),
                              onPressed: c.sos,
                              icon: const Icon(Icons.sos),
                              label: Text('tracking.sos'.tr),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (j.status == JobStatus.completed && j.can(JobActions.rate)) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('tracking.rate'),
                      onPressed: c.rate,
                      icon: const Icon(Icons.star),
                      label: Text('tracking.rate'.tr),
                    ),
                  ],
                  const SizedBox(height: 16),
                  StopsCard(pickup: j.pickup, dropoff: j.dropoff),
                  const SizedBox(height: 12),
                  _Details(job: j),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: JobTimeline(job: j),
                    ),
                  ),
                  if (j.proofUrl != null) ...[SectionTitle('tracking.proof'.tr), GoImage(j.proofUrl, height: 220)],
                  if (j.can(JobActions.cancel)) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      key: const Key('tracking.cancel'),
                      onPressed: c.busy.value ? null : c.cancel,
                      style: TextButton.styleFrom(foregroundColor: GoColors.danger),
                      child: Text('tracking.cancel'.tr),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.job, required this.eta});
  final Job job;
  final String? eta;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'status.${job.status.wire}'.tr,
        key: const Key('tracking.status'),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      ),
      if (eta != null)
        Text(
          'tracking.eta'.trParams({'eta': eta!}),
          style: const TextStyle(color: GoColors.primary, fontWeight: FontWeight.w600),
        ),
      if (job.status == JobStatus.cancelled && job.cancelReason != null)
        Text(job.cancelReason!, style: const TextStyle(color: GoColors.danger)),
    ],
  );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.job, required this.onRetry});
  final Job job;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = job.payment.status == PaymentStatus.failed;
    return Card(
      color: failed ? GoColors.danger.withValues(alpha: 0.08) : GoColors.accent.withValues(alpha: 0.12),
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              failed ? 'error.payment_failed'.tr : 'tracking.waiting_payment'.trParams({'method': 'payment.${job.payment.method.name}'.tr}),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: Text('tracking.open_payment'.tr)),
          ],
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.job, required this.busy, required this.onConfirm});
  final Job job;
  final bool busy;
  final ValueChanged<bool> onConfirm;

  @override
  Widget build(BuildContext context) {
    final p = job.pabili!;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('tracking.receipt_title'.tr, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            GoImage(p.receiptUrl, height: 260, fit: BoxFit.contain, icon: Icons.receipt_long),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('tracking.item_total'.tr)),
                MoneyText(p.itemTotalCentavos ?? 0, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('tracking.confirm_items'),
              onPressed: busy ? null : () => onConfirm(true),
              child: Text('tracking.confirm_items'.tr),
            ),
            TextButton(onPressed: busy ? null : () => onConfirm(false), child: Text('tracking.dispute'.tr)),
          ],
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (job.food != null) ...[
            Text(job.merchant?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final l in job.food!.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.quantity}×  '),
                    Expanded(child: Text([l.name, ...l.addons].join(', '))),
                    MoneyText(l.lineTotalCentavos),
                  ],
                ),
              ),
            const Divider(height: 20),
          ],
          if (job.pabili != null) ...[
            Text(job.pabili!.storeName, style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final i in job.pabili!.items) Text('• ${i.quantity}× ${i.name}${i.note == null ? '' : ' (${i.note})'}'),
            const Divider(height: 20),
          ],
          if (job.padala != null) ...[
            Text('${'padala.size.${job.padala!.size.name}'.tr} · ${job.padala!.description}'),
            Text('${'padala.recipient'.tr}: ${job.padala!.recipientName}'),
            const Divider(height: 20),
          ],
          FareBreakdown(
            lines: [for (final l in job.fare.breakdown) (label: l.label, amount: l.amountCentavos)],
            total: job.fare.totalCentavos,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('payment.${job.payment.method.name}'.tr),
              const Spacer(),
              StatusChip(
                'payment.${job.payment.status.name}'.tr,
                color: job.payment.status == PaymentStatus.paid ? GoColors.success : GoColors.warning,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
