import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class OrderView extends GetView<OrderController> {
  const OrderView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Obx(() {
      final o = c.order.value;
      if (o == null) {
        return Scaffold(
          appBar: AppBar(),
          body: c.error.value == null ? const LoadingState() : ErrorState(error: c.error.value!, onRetry: c.load),
        );
      }
      final isNew = o.status == MerchantOrderStatus.newOrder;
      return Scaffold(
        appBar: AppBar(
          title: Text(o.code, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                StatusChip('merchant.status.${o.status.wire}'.tr),
                const Spacer(),
                if (isNew && o.merchantAcceptDeadline != null)
                  CountdownText(
                    deadline: o.merchantAcceptDeadline!,
                    builder: (_, left) => Text(
                      'merchant.auto_reject_in'.trParams({'t': '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}'}),
                      style: const TextStyle(color: GoColors.danger, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${'merchant.customer'.tr}: ${o.customerFirstName} · ${formatManilaTime(o.createdAt)}'),
            if (o.prepTimeMinutes != null) Text('merchant.prep_is'.trParams({'m': '${o.prepTimeMinutes}'})),
            if (o.rider != null) ...[
              SectionTitle('merchant.handoff'.tr),
              Card(
                key: const Key('order.rider'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      GoImage(o.rider!.photoUrl, width: 56, height: 56, radius: 28, icon: Icons.person),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.rider!.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            Text('rider.card.plate'.trParams({'plate': o.rider!.plate})),
                            Text(o.rider!.phoneMasked, style: TextStyle(color: GoColors.muted)),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Text('merchant.match_code'.tr, style: TextStyle(fontSize: 11, color: GoColors.muted)),
                          Text(o.code, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final l in o.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${l.quantity}×', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                                  for (final a in l.addons) Text('+ $a', style: TextStyle(color: GoColors.muted)),
                                  if (l.note != null)
                                    Text(
                                      '“${l.note}”',
                                      style: const TextStyle(color: GoColors.danger, fontWeight: FontWeight.w600),
                                    ),
                                ],
                              ),
                            ),
                            MoneyText(l.lineTotalCentavos),
                          ],
                        ),
                      ),
                    if (o.notes != null) ...[
                      const Divider(height: 20),
                      Text('${'common.notes'.tr}: ${o.notes}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                    const Divider(height: 20),
                    FareBreakdown(
                      lines: [
                        (label: 'common.subtotal'.tr, amount: o.subtotalCentavos),
                        (label: 'merchant.commission'.tr, amount: -o.commissionCentavos),
                      ],
                      total: o.netCentavos,
                    ),
                    const SizedBox(height: 8),
                    Text('${'common.payment'.tr}: ${'payment.${o.paymentMethod.name}'.tr}'),
                  ],
                ),
              ),
            ),
            if (o.riderPaysAtPickupCentavos != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: GoColors.accent, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    const Icon(Icons.payments),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('merchant.rider_pays'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    MoneyText(o.riderPaysAtPickupCentavos!, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
            if (o.rejectReason != null) ...[
              const SizedBox(height: 12),
              Text('merchant.reject.${o.rejectReason!.wire}'.tr, style: const TextStyle(color: GoColors.danger)),
            ],
            const SizedBox(height: 100),
          ],
        ),
        bottomNavigationBar: o.allowedActions.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (o.can(OrderActions.reject))
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('order.reject'),
                            style: OutlinedButton.styleFrom(foregroundColor: GoColors.danger, minimumSize: const Size.fromHeight(60)),
                            onPressed: c.busy.value ? null : c.reject,
                            child: Text('merchant.reject_order'.tr),
                          ),
                        ),
                      if (o.can(OrderActions.reject)) const SizedBox(width: 12),
                      if (o.can(OrderActions.accept))
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 60,
                            child: FilledButton(
                              key: const Key('order.accept'),
                              onPressed: c.busy.value ? null : c.accept,
                              child: Text('merchant.accept_order'.tr),
                            ),
                          ),
                        ),
                      if (o.can(OrderActions.ready))
                        Expanded(
                          child: SizedBox(
                            height: 60,
                            child: FilledButton(
                              key: const Key('order.ready'),
                              style: FilledButton.styleFrom(backgroundColor: GoColors.success),
                              onPressed: c.busy.value ? null : c.markReady,
                              child: Text('merchant.mark_ready'.tr),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      );
    });
  }
}
