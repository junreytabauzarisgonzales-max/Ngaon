import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class WalletView extends GetView<WalletController> {
  const WalletView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text('rider.wallet'.tr)),
      body: Obx(() {
        final w = c.wallet.value;
        if (c.loading.value && w == null) return const LoadingState();
        if (c.error.value != null && w == null) return ErrorState(error: c.error.value!, onRetry: c.load);
        final low = w != null && w.balanceCentavos < w.minBalanceCentavos;
        return RefreshIndicator(
          onRefresh: c.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, goNavBarClearance),
            children: [
              Card(
                color: GoColors.night,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('rider.commission_balance'.tr, style: const TextStyle(color: Colors.white70)),
                      MoneyText(
                        w?.balanceCentavos ?? 0,
                        style: TextStyle(color: low ? GoColors.accent : Colors.white, fontSize: 34, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'rider.min_balance'.trParams({'min': formatCentavos(w?.minBalanceCentavos ?? 0)}),
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('wallet.topup'),
                        style: FilledButton.styleFrom(backgroundColor: GoColors.accent, foregroundColor: GoColors.night),
                        onPressed: () => showGoSheet<void>(
                          title: 'rider.topup'.tr,
                          child: TopupSheet(controller: c),
                        ),
                        icon: const Icon(Icons.add),
                        label: Text('rider.topup'.tr),
                      ),
                    ],
                  ),
                ),
              ),
              SectionTitle('rider.transactions'.tr),
              for (final t in c.txs)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(switch (t.type) {
                      WalletTxType.topup => Icons.add_circle,
                      WalletTxType.commission => Icons.remove_circle,
                      WalletTxType.earning => Icons.payments,
                      WalletTxType.payout => Icons.account_balance,
                      WalletTxType.adjustment => Icons.tune,
                    }, color: t.amountCentavos >= 0 ? GoColors.success : GoColors.danger),
                    title: Text(t.note ?? 'rider.tx.${t.type.name}'.tr),
                    subtitle: Text(formatManilaDateTime(t.createdAt)),
                    trailing: MoneyText(t.amountCentavos, showSign: true, style: const TextStyle(fontWeight: FontWeight.w700)),
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

class TopupSheet extends StatefulWidget {
  const TopupSheet({super.key, required this.controller});
  final WalletController controller;
  @override
  State<TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends State<TopupSheet> {
  int _amount = 20000;
  PaymentMethod _method = PaymentMethod.gcash;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Padding(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final a in const [10000, 20000, 50000, 100000])
                ChoiceChip(label: Text(formatCentavos(a)), selected: _amount == a, onSelected: (_) => setState(() => _amount = a)),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<PaymentMethod>(
            segments: [
              ButtonSegment(value: PaymentMethod.gcash, label: Text('payment.gcash'.tr)),
              ButtonSegment(value: PaymentMethod.maya, label: Text('payment.maya'.tr)),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: 16),
          Obx(
            () => FilledButton(
              onPressed: widget.controller.topupBusy.value ? null : () => widget.controller.topUp(_amount, _method),
              child: Text('rider.topup_pay'.trParams({'amount': formatCentavos(_amount)})),
            ),
          ),
        ],
      ),
    ),
  );
}
