import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class PayoutsView extends GetView<PayoutsController> {
  const PayoutsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text('merchant.payouts'.tr)),
      body: Obx(() {
        if (c.loading.value && c.items.isEmpty) return const LoadingState();
        if (c.error.value != null && c.items.isEmpty) return ErrorState(error: c.error.value!, onRetry: c.load);
        if (c.items.isEmpty) return EmptyState(message: 'common.empty'.tr);
        return PagedListView<Payout>(
          items: c.items.toList(),
          hasMore: c.hasMore,
          onRefresh: c.load,
          onLoadMore: () => c.load(more: true),
          padding: const EdgeInsets.all(16),
          itemBuilder: (_, p) {
            final invoice = p.type == PayoutType.commissionInvoice;
            return Card(
              child: ListTile(
                leading: Icon(invoice ? Icons.request_quote : Icons.account_balance, color: invoice ? GoColors.warning : GoColors.success),
                title: Text('merchant.payout_type.${p.type.wire}'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${p.periodFrom} → ${p.periodTo}${p.paidAt != null ? '\n${'payment.paid'.tr} ${formatManilaDate(p.paidAt!)}' : ''}',
                ),
                isThreeLine: p.paidAt != null,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(p.amountCentavos, style: const TextStyle(fontWeight: FontWeight.w800)),
                    StatusChip(
                      'merchant.payout_status.${p.status.name}'.tr,
                      color: switch (p.status) {
                        PayoutStatus.paid => GoColors.success,
                        PayoutStatus.overdue => GoColors.danger,
                        PayoutStatus.pending => GoColors.warning,
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
