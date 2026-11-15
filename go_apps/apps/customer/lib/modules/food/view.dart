import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import 'controller.dart';

class FoodView extends GetView<FoodController> {
  const FoodView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text('service.food'.tr)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: Get.arguments is Map && (Get.arguments as Map)['search'] == true,
              decoration: InputDecoration(hintText: 'food.search_hint'.tr, prefixIcon: const Icon(Icons.search)),
              onChanged: c.search,
            ),
          ),
          Expanded(
            child: Obx(() {
              if (c.loading.value && c.merchants.isEmpty) return const LoadingState();
              if (c.error.value != null && c.merchants.isEmpty) return ErrorState(error: c.error.value!, onRetry: c.load);
              if (c.merchants.isEmpty) return EmptyState(icon: Icons.storefront, message: 'food.no_merchants'.tr);
              return PagedListView<Merchant>(
                items: c.merchants.toList(),
                hasMore: c.hasMore,
                onRefresh: c.load,
                onLoadMore: () => c.load(more: true),
                itemBuilder: (_, m) => _MerchantCard(merchant: m, onTap: () => c.open(m)),
              );
            }),
          ),
        ],
      ),
      floatingActionButton: Obx(
        () => c.cart.isEmpty
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                onPressed: () => Get.toNamed(Routes.cart),
                icon: Badge(label: Text('${c.cart.count}'), child: const Icon(Icons.shopping_bag)),
                label: Text(formatCentavos(c.cart.subtotal)),
              ),
      ),
    );
  }
}

class _MerchantCard extends StatelessWidget {
  const _MerchantCard({required this.merchant, required this.onTap});
  final Merchant merchant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final open = merchant.acceptsOrders;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: open ? 1 : 0.55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GoImage(merchant.coverUrl, height: 120, width: double.infinity, radius: 0, icon: Icons.storefront),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    GoImage(merchant.logoUrl, width: 44, height: 44, radius: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(merchant.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          Text(
                            [
                              if (merchant.rating != null) '★ ${merchant.rating!.toStringAsFixed(1)}',
                              '${merchant.prepTimeMinutes} ${'common.min'.tr}',
                              if (merchant.distanceM != null) formatDistance(merchant.distanceM!),
                            ].join(' · '),
                            style: TextStyle(color: GoColors.muted),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(
                      open ? 'food.open'.tr : (merchant.isPaused ? 'food.paused'.tr : 'food.closed'.tr),
                      color: open ? GoColors.success : GoColors.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
