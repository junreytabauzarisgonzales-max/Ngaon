import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class SalesView extends GetView<SalesController> {
  const SalesView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text('merchant.sales'.tr)),
      body: Obx(() {
        final r = c.report.value;
        return RefreshIndicator(
          onRefresh: c.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, goNavBarClearance),
            children: [
              SegmentedButton<SalesRange>(
                segments: [
                  ButtonSegment(value: SalesRange.today, label: Text('common.today'.tr)),
                  ButtonSegment(value: SalesRange.week, label: Text('common.this_week'.tr)),
                  ButtonSegment(value: SalesRange.custom, label: Text('common.custom'.tr)),
                ],
                selected: {c.range.value},
                onSelectionChanged: (s) => c.select(s.first),
              ),
              const SizedBox(height: 12),
              if (c.loading.value && r == null) const LoadingState(),
              if (c.error.value != null && r == null) ErrorState(error: c.error.value!, onRetry: c.load),
              if (r != null) ...[
                Text('${r.from} → ${r.to}', style: TextStyle(color: GoColors.muted)),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width >= 720 ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.8,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    _Tile('merchant.orders_count'.tr, '${r.ordersCount}'),
                    _Tile('merchant.gross'.tr, formatCentavos(r.grossCentavos)),
                    _Tile('merchant.commission'.tr, formatCentavos(r.commissionCentavos)),
                    _Tile('merchant.net'.tr, formatCentavos(r.netCentavos), strong: true),
                  ],
                ),
                SectionTitle('merchant.daily'.tr),
                Card(
                  child: Column(
                    children: [
                      for (final d in r.days)
                        ListTile(
                          dense: true,
                          title: Text(d.date),
                          subtitle: Text('merchant.orders_n'.trParams({'n': '${d.ordersCount}'})),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              MoneyText(d.netCentavos, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(formatCentavos(d.grossCentavos), style: TextStyle(fontSize: 11, color: GoColors.muted)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      }),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.strong = false});
  final String label;
  final String value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Card(
    color: strong ? GoColors.primary : null,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(color: strong ? Colors.white70 : GoColors.muted)),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: strong ? Colors.white : GoColors.ink),
            ),
          ),
        ],
      ),
    ),
  );
}
