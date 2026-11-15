import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class ActiveJobView extends GetView<ActiveJobController> {
  const ActiveJobView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final done = c.completed.value;
      if (done != null) return _Done(job: done);
      final j = c.job;
      if (j == null) {
        return Scaffold(
          appBar: AppBar(),
          body: EmptyState(message: 'rider.no_active_job'.tr),
        );
      }
      final step = riderNextStep(j);
      final waitKey = step == null ? riderWaitingReasonKey(j) : null;
      final cash = j.payment.method == PaymentMethod.cash;
      final toPickup = identical(c.target, j.pickup);
      return Scaffold(
        appBar: AppBar(title: Text('${'service.${j.service.name}'.tr} · ${j.code}')),
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: 200,
              child: GoMap(
                center: c.target.location,
                interactive: false,
                markers: [
                  GoMarker('p', j.pickup.location, j.service == ServiceType.food ? MarkerKind.store : MarkerKind.pickup),
                  GoMarker('d', j.dropoff.location, MarkerKind.dropoff),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'status.${j.status.wire}'.tr,
                    key: const Key('job.status'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: Icon(toPickup ? Icons.trip_origin : Icons.location_on, color: toPickup ? GoColors.primary : GoColors.danger),
                      title: Text(
                        toPickup ? 'rider.go_pickup'.tr : 'rider.go_dropoff'.tr,
                        style: TextStyle(fontSize: 12, color: GoColors.muted),
                      ),
                      subtitle: Text(
                        c.target.address,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: GoColors.ink),
                      ),
                      trailing: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: c.navigate,
                        icon: const Icon(Icons.navigation),
                        label: Text('common.navigate'.tr),
                      ),
                    ),
                  ),
                  if (c.target.notes != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${c.target.notes}”')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (j.can(JobActions.chat))
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: c.chat,
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: Text('common.chat'.tr),
                          ),
                        ),
                      const SizedBox(width: 12),
                      if (j.can(JobActions.call))
                        Expanded(
                          child: OutlinedButton.icon(onPressed: c.call, icon: const Icon(Icons.call), label: Text('common.call'.tr)),
                        ),
                    ],
                  ),
                  if (j.food != null) _FoodCard(job: j),
                  if (j.pabili != null) _PabiliCard(job: j),
                  if (j.padala != null)
                    Card(
                      margin: const EdgeInsets.only(top: 12),
                      child: ListTile(
                        leading: const Icon(Icons.inventory_2),
                        title: Text(j.padala!.description),
                        subtitle: Text('${'padala.size'.tr}: ${j.padala!.size.name} · ${j.padala!.recipientName}'),
                      ),
                    ),
                  if (cash) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: GoColors.accent, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          const Icon(Icons.payments, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('rider.collect'.tr, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          ),
                          Text(
                            formatCentavos(j.fare.totalCentavos),
                            key: const Key('job.collect'),
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  StopsCard(pickup: j.pickup, dropoff: j.dropoff),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: step == null
                ? Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: GoColors.line, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Expanded(child: Text((waitKey ?? 'rider.wait.generic').tr, key: const Key('job.waiting'))),
                      ],
                    ),
                  )
                : SizedBox(
                    height: 64,
                    child: FilledButton(
                      key: const Key('job.primary'),
                      onPressed: c.busy.value ? null : () => c.advance(step),
                      child: c.busy.value
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(step.labelKey.tr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ),
                  ),
          ),
        ),
      );
    });
  }
}

class _FoodCard extends StatelessWidget {
  const _FoodCard({required this.job});
  final Job job;
  @override
  Widget build(BuildContext context) {
    final f = job.food!;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(job.merchant?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                StatusChip(
                  f.isReady ? 'rider.food_ready'.tr : 'rider.food_preparing'.tr,
                  color: f.isReady ? GoColors.success : GoColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final l in f.items) Text('${l.quantity}× ${[l.name, ...l.addons].join(', ')}${l.note == null ? '' : ' — “${l.note}”'}'),
            if (f.riderPaysMerchantCentavos != null) ...[
              const Divider(height: 20),
              Row(
                children: [
                  const Icon(Icons.storefront, color: GoColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('rider.pay_merchant'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text(formatCentavos(f.riderPaysMerchantCentavos!), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PabiliCard extends StatelessWidget {
  const _PabiliCard({required this.job});
  final Job job;
  @override
  Widget build(BuildContext context) {
    final p = job.pabili!;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.storeName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            for (final i in p.items) Text('☐ ${i.quantity}× ${i.name}${i.note == null ? '' : ' (${i.note})'}'),
            if (p.itemTotalCentavos != null) ...[
              const Divider(height: 20),
              Row(
                children: [
                  Expanded(child: Text('rider.receipt.total'.tr)),
                  MoneyText(p.itemTotalCentavos!, style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.job});
  final Job job;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            const Icon(Icons.check_circle, color: GoColors.success, size: 96),
            const SizedBox(height: 16),
            Text(
              'rider.job_done'.tr,
              key: const Key('job.done'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            ),
            Text(
              job.code,
              textAlign: TextAlign.center,
              style: TextStyle(color: GoColors.muted),
            ),
            const Spacer(),
            FilledButton(onPressed: Get.back, child: Text('rider.back_online'.tr)),
          ],
        ),
      ),
    ),
  );
}
