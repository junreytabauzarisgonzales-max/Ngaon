import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class CheckoutView extends GetView<CheckoutController> {
  const CheckoutView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final req = c.args.request;
    return Scaffold(
      appBar: AppBar(title: Text(c.args.title)),
      body: Obx(() {
        if (c.loading.value) return const LoadingState();
        final q = c.quote.value;
        if (q == null) return ErrorState(error: c.error.value ?? 'x', onRetry: c.fetchQuote);
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          children: [
            StopsCard(pickup: req.pickup, dropoff: req.dropoff),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Wraps on narrow phones instead of overflowing.
                    Wrap(
                      spacing: 4,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Stat(icon: Icons.route, text: formatDistance(q.distanceM)),
                        _Stat(icon: Icons.schedule, text: formatDuration(q.durationS)),
                        CountdownText(
                          deadline: q.expiresAt,
                          onExpired: c.fetchQuote,
                          builder: (_, left) => Text(
                            'checkout.price_valid'.trParams({'m': '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}'}),
                            style: TextStyle(color: GoColors.muted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    FareBreakdown(lines: [for (final l in q.breakdown) (label: l.label, amount: l.amountCentavos)], total: q.totalCentavos),
                    if (q.maxItemBudgetCentavos != null) ...[
                      const SizedBox(height: 12),
                      _Note(
                        text: 'checkout.pabili_note'.trParams({'max': formatCentavos(q.maxItemBudgetCentavos!)}),
                        color: c.budgetTooHigh ? GoColors.danger : GoColors.muted,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SectionTitle('common.payment'.tr),
            Card(
              child: RadioGroup<PaymentMethod>(
                groupValue: c.method.value,
                onChanged: (v) => c.method.value = v!,
                child: Column(
                  children: [
                    for (final m in PaymentMethod.values)
                      RadioListTile<PaymentMethod>(
                        value: m,
                        title: Text('payment.${m.name}'.tr),
                        subtitle: Text('checkout.pay_${m.name}'.tr),
                        secondary: Icon(m == PaymentMethod.cash ? Icons.payments_outlined : Icons.account_balance_wallet_outlined),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(labelText: 'checkout.notes'.tr, hintText: 'checkout.notes_hint'.tr),
              maxLines: 2,
              onChanged: (v) => c.notes.value = v,
            ),
            const SizedBox(height: 100),
          ],
        );
      }),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Obx(() {
            final q = c.quote.value;
            return FilledButton(
              key: const Key('checkout.place'),
              onPressed: q == null || c.placing.value || c.budgetTooHigh ? null : c.place,
              child: c.placing.value
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text(q == null ? 'checkout.book'.tr : 'checkout.book_for'.trParams({'total': formatCentavos(q.totalCentavos)})),
            );
          }),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 16),
    child: Row(
      children: [
        Icon(icon, size: 18, color: GoColors.muted),
        const SizedBox(width: 4),
        Text(text),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(Icons.info_outline, size: 18, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text, style: TextStyle(color: color)),
      ),
    ],
  );
}
