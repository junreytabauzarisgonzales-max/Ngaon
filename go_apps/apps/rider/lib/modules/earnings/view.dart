import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class EarningsView extends GetView<EarningsController> {
  const EarningsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text('rider.earnings'.tr)),
      body: Obx(() {
        final e = c.earnings.value;
        if (c.loading.value && e == null) return const LoadingState();
        if (c.error.value != null && e == null) return ErrorState(error: c.error.value!, onRetry: c.load);
        return RefreshIndicator(
          onRefresh: c.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, goNavBarClearance),
            children: [
              SegmentedButton<EarningsRange>(
                segments: [
                  ButtonSegment(value: EarningsRange.today, label: Text('common.today'.tr)),
                  ButtonSegment(value: EarningsRange.week, label: Text('common.this_week'.tr)),
                ],
                selected: {c.range.value},
                onSelectionChanged: (s) => c.range.value = s.first,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      MoneyText(e?.totalCentavos ?? 0, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
                      Text('rider.jobs_count'.trParams({'n': '${e?.jobsCount ?? 0}'}), style: TextStyle(color: GoColors.muted)),
                    ],
                  ),
                ),
              ),
              if (c.range.value == EarningsRange.week && e != null) ...[
                SectionTitle('rider.by_day'.tr),
                Card(
                  child: Column(
                    children: [
                      for (final d in e.days)
                        ListTile(
                          dense: true,
                          title: Text(d.date),
                          subtitle: Text('rider.jobs_count'.trParams({'n': '${d.jobsCount}'})),
                          trailing: MoneyText(d.totalCentavos, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                ),
              ],
              SectionTitle('rider.jobs'.tr),
              if (c.jobs.isEmpty) EmptyState(message: 'common.empty'.tr),
              for (final j in c.jobs)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(serviceIcon(j.service.name), color: serviceColor(j.service.name)),
                    title: Text('${j.code} · ${'status.${j.status.wire}'.tr}'),
                    subtitle: Text('${formatManilaDateTime(j.createdAt)}\n${j.dropoff.address}'),
                    isThreeLine: true,
                    trailing: MoneyText(j.fare.totalCentavos),
                  ),
                ),
              if (c.hasMore) TextButton(onPressed: () => c.load(more: true), child: Text('common.load_more'.tr)),
            ],
          ),
        );
      }),
    );
  }
}
