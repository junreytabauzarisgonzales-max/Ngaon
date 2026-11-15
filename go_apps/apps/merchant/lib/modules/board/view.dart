import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/merchant_session_service.dart';
import '../menu/sold_out_sheet.dart';
import 'controller.dart';

/// Orders board: columns on tablets (>= 720 dp), tabs on phones.
class BoardView extends GetView<BoardController> {
  const BoardView({super.key});

  @override
  Widget build(BuildContext context) {
    final s = controller.session;
    final columns = [
      ('merchant.col.new', s.newOrders, GoColors.danger),
      ('merchant.col.preparing', s.preparing, GoColors.warning),
      ('merchant.col.ready', s.ready, GoColors.success),
      ('merchant.col.done', s.done, GoColors.muted),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Obx(() => Text(s.store.value?.name ?? '')),
        actions: [
          IconButton(
            key: const Key('board.sold_out'),
            tooltip: 'merchant.sold_out'.tr,
            icon: const Icon(Icons.remove_shopping_cart_outlined),
            onPressed: () => showGoSheet<void>(title: 'merchant.sold_out'.tr, tall: true, child: const SoldOutSheet()),
          ),
        ],
      ),
      body: Column(
        children: [
          _StoreBar(controller: controller),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth >= 720) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (k, list, color) in columns)
                        Expanded(
                          child: Column(
                            children: [
                              _ColumnHeader(title: k.tr, list: list, color: color),
                              Expanded(
                                child: _OrderList(list: list, onRefresh: controller.refreshBoard),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                }
                return DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [for (final (k, list, _) in columns) Tab(child: Obx(() => Text('${k.tr} (${list.length})')))],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [for (final (_, list, _) in columns) _OrderList(list: list, onRefresh: controller.refreshBoard)],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreBar extends StatelessWidget {
  const _StoreBar({required this.controller});
  final BoardController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final m = controller.session.store.value;
    if (m == null) return const SizedBox.shrink();
    final paused = m.isPaused;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: m.isOpen ? (paused ? GoColors.warning : GoColors.success) : GoColors.night,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.isOpen ? (paused ? 'merchant.paused'.tr : 'merchant.open'.tr) : 'merchant.closed'.tr,
                  key: const Key('board.store_status'),
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                ),
                if (paused)
                  Text(
                    'merchant.paused_until'.trParams({'t': formatManilaTime(m.pausedUntil!)}),
                    style: const TextStyle(color: Colors.white),
                  ),
              ],
            ),
          ),
          if (m.isOpen)
            PopupMenuButton<int?>(
              tooltip: 'merchant.pause'.tr,
              icon: const Icon(Icons.pause_circle_outline, color: Colors.white, size: 30),
              onSelected: controller.pause,
              itemBuilder: (_) => [
                for (final m in const [15, 30, 60]) PopupMenuItem(value: m, child: Text('merchant.pause_for'.trParams({'m': '$m'}))),
                if (paused) PopupMenuItem(value: null, child: Text('merchant.resume'.tr)),
              ],
            ),
          Transform.scale(
            scale: 1.3,
            child: Switch(
              key: const Key('board.open_switch'),
              value: m.isOpen,
              activeThumbColor: Colors.white,
              onChanged: controller.toggleOpen,
            ),
          ),
        ],
      ),
    );
  });
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.title, required this.list, required this.color});
  final String title;
  final RxList<MerchantOrder> list;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Obx(
      () => Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$title (${list.length})',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OrderList extends StatelessWidget {
  const _OrderList({required this.list, required this.onRefresh});
  final RxList<MerchantOrder> list;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: Obx(
      () => list.isEmpty
          ? ListView(
              children: [
                SizedBox(
                  height: 240,
                  child: EmptyState(icon: Icons.receipt_long_outlined, message: 'merchant.no_orders'.tr),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, goNavBarClearance),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => OrderCard(order: list[i]),
            ),
    ),
  );
}

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order});
  final MerchantOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final isNew = o.status == MerchantOrderStatus.newOrder;
    return Card(
      key: Key('order.${o.code}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isNew ? const BorderSide(color: GoColors.danger, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Get.find<MerchantSessionService>().open(o),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      o.code,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                  if (isNew && o.merchantAcceptDeadline != null)
                    CountdownText(
                      deadline: o.merchantAcceptDeadline!,
                      style: const TextStyle(color: GoColors.danger, fontWeight: FontWeight.w800, fontSize: 16),
                    )
                  else
                    Flexible(
                      child: StatusChip(
                        'merchant.status.${o.status.wire}'.tr,
                        color: o.status == MerchantOrderStatus.rejected || o.status == MerchantOrderStatus.cancelled
                            ? GoColors.danger
                            : GoColors.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${o.customerFirstName} · ${'merchant.items_n'.trParams({'n': '${o.itemCount}'})} · ${'payment.${o.paymentMethod.name}'.tr}',
              ),
              const SizedBox(height: 4),
              for (final l in o.items.take(3))
                Text(
                  '${l.quantity}× ${l.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: GoColors.muted),
                ),
              if (o.items.length > 3) Text('+${o.items.length - 3}…', style: TextStyle(color: GoColors.muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MoneyText(o.subtotalCentavos, style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (o.rider != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [const Icon(Icons.two_wheeler, size: 18), const SizedBox(width: 4), Text(o.rider!.name)],
                    ),
                  Text(formatManilaTime(o.createdAt), style: TextStyle(color: GoColors.muted, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
