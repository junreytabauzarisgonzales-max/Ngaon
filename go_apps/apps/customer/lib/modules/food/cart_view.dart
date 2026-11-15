import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/widgets/stop_field.dart';
import 'cart_controller.dart';

class CartView extends GetView<CartController> {
  const CartView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final cart = c.cart;
    return Scaffold(
      appBar: AppBar(title: Obx(() => Text(cart.merchantName.value))),
      body: Obx(() {
        if (cart.isEmpty) return EmptyState(icon: Icons.shopping_bag_outlined, message: 'food.cart_empty'.tr);
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  for (final l in cart.lines)
                    ListTile(
                      title: Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([...l.addonNames, if (l.note != null) '“${l.note}”'].join(', ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(onPressed: () => cart.changeQty(l, -1), icon: const Icon(Icons.remove_circle_outline)),
                          Text('${l.quantity}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          IconButton(onPressed: () => cart.changeQty(l, 1), icon: const Icon(Icons.add_circle_outline)),
                          SizedBox(width: 80, child: Text(formatCentavos(l.totalCentavos), textAlign: TextAlign.end)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('common.subtotal'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    MoneyText(cart.subtotal, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  ],
                ),
              ),
            ),
            if (c.belowMin)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'food.min_order'.trParams({'min': formatCentavos(cart.minOrderCentavos.value)}),
                  style: const TextStyle(color: GoColors.danger),
                ),
              ),
            const SizedBox(height: 12),
            StopField(label: 'common.dropoff'.tr, stop: c.dropoff.value, color: GoColors.danger, onPicked: (s) => c.dropoff.value = s),
            TextButton(
              onPressed: () async {
                if (await confirmDialog(title: 'food.clear_cart'.tr, danger: true)) cart.clear();
              },
              child: Text('food.clear_cart'.tr),
            ),
          ],
        );
      }),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Obx(
            () => FilledButton(
              key: const Key('cart.checkout'),
              onPressed: cart.isEmpty || c.belowMin || c.dropoff.value == null || c.merchant.value == null ? null : c.checkout,
              child: Text('food.checkout'.tr),
            ),
          ),
        ),
      ),
    );
  }
}
