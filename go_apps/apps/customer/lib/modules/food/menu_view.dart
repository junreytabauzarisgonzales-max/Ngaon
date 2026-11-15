import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../../app/services/cart_service.dart';
import 'controller.dart';

class MenuView extends GetView<MerchantMenuController> {
  const MenuView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      body: Obx(() {
        if (c.loading.value) return const Scaffold(body: LoadingState());
        final m = c.merchant.value;
        if (m == null) {
          return Scaffold(
            appBar: AppBar(),
            body: ErrorState(error: c.error.value ?? 'x', onRetry: c.load),
          );
        }
        final cats = [...?m.menu]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 180,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  m.name,
                  style: const TextStyle(color: Colors.white, shadows: [Shadow(blurRadius: 6)]),
                ),
                background: GoImage(m.coverUrl, radius: 0),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.address, style: TextStyle(color: GoColors.muted)),
                    const SizedBox(height: 4),
                    Text('food.prep_min_order'.trParams({'prep': '${m.prepTimeMinutes}', 'min': formatCentavos(m.minOrderCentavos)})),
                    if (!m.acceptsOrders)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: StatusChip(m.isPaused ? 'food.paused'.tr : 'food.closed_now'.tr, color: GoColors.danger),
                      ),
                  ],
                ),
              ),
            ),
            for (final cat in cats) ...[
              SliverToBoxAdapter(child: SectionTitle(cat.name)),
              SliverList.separated(
                itemCount: cat.items.length,
                separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
                itemBuilder: (_, i) => _ItemRow(item: cat.items[i], enabled: m.acceptsOrders, onTap: () => _openItem(cat.items[i])),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        );
      }),
      bottomNavigationBar: Obx(() {
        final cart = c.cart;
        if (cart.isEmpty || cart.merchantId.value != c.merchantId) return const SizedBox.shrink();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              key: const Key('menu.view_cart'),
              onPressed: () => Get.toNamed(Routes.cart),
              child: Text('food.view_cart'.trParams({'n': '${cart.count}', 'total': formatCentavos(cart.subtotal)})),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _openItem(MenuItem item) async {
    final line = await showGoSheet<CartLine>(tall: true, child: ItemSheet(item: item));
    if (line != null) await controller.addToCart(line);
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.enabled, required this.onTap});
  final MenuItem item;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final available = item.isAvailable && enabled;
    return InkWell(
      onTap: available ? onTap : null,
      child: Opacity(
        opacity: item.isAvailable ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    if (item.description != null)
                      Text(
                        item.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: GoColors.muted),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        MoneyText(item.priceCentavos, style: const TextStyle(fontWeight: FontWeight.w700)),
                        if (!item.isAvailable) ...[const SizedBox(width: 8), StatusChip('food.sold_out'.tr, color: GoColors.danger)],
                      ],
                    ),
                  ],
                ),
              ),
              if (item.photoUrl != null) ...[const SizedBox(width: 12), GoImage(item.photoUrl, width: 72, height: 72)],
            ],
          ),
        ),
      ),
    );
  }
}

/// Item configuration: add-on groups with min/max, quantity, note.
class ItemSheet extends StatefulWidget {
  const ItemSheet({super.key, required this.item});
  final MenuItem item;
  @override
  State<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<ItemSheet> {
  final Map<String, Set<String>> _selected = {};
  int _qty = 1;
  final _note = TextEditingController();

  MenuItem get item => widget.item;

  Iterable<AddonOption> get _chosen => item.addonGroups.expand((g) => g.options.where((o) => _selected[g.id]?.contains(o.id) ?? false));

  int get _unit => item.priceCentavos + _chosen.fold(0, (s, o) => s + o.priceCentavos);

  bool get _valid => item.addonGroups.every((g) {
    final n = _selected[g.id]?.length ?? 0;
    return n >= g.minSelect && n <= g.maxSelect;
  });

  void _toggle(AddonGroup g, AddonOption o) {
    final set = _selected.putIfAbsent(g.id, () => {});
    setState(() {
      if (set.contains(o.id)) {
        set.remove(o.id);
      } else if (g.maxSelect == 1) {
        set
          ..clear()
          ..add(o.id);
      } else if (set.length < g.maxSelect) {
        set.add(o.id);
      }
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (item.photoUrl != null) ...[
              GoImage(item.photoUrl, height: 180, width: double.infinity, radius: 20),
              const SizedBox(height: 14),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(item.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                MoneyText(item.priceCentavos, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
            if (item.description != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(item.description!, style: TextStyle(color: GoColors.muted, fontSize: 15)),
              ),
            for (final g in item.addonGroups) _group(g),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: 'food.item_note'.tr, hintText: 'food.item_note_hint'.tr),
            ),
          ],
        ),
      ),
      // Sticky footer: quantity stepper + add button with live total.
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: GoColors.surface,
          border: Border(top: BorderSide(color: GoColors.line)),
        ),
        child: Row(
          children: [
            _Stepper(qty: _qty, onChanged: (q) => setState(() => _qty = q)),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('item.add'),
                onPressed: _valid ? _add : null,
                child: Text(_valid ? 'food.add'.trParams({'total': formatCentavos(_unit * _qty)}) : 'food.choose_required'.tr),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  void _add() => Get.back(
    result: CartLine(
      itemId: item.id,
      name: item.name,
      unitCentavos: _unit,
      quantity: _qty,
      addonOptionIds: _chosen.map((o) => o.id).toList(),
      addonNames: _chosen.map((o) => o.name).toList(),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    ),
  );

  Widget _group(AddonGroup g) {
    final picked = _selected[g.id]?.length ?? 0;
    final satisfied = picked >= g.minSelect;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              ),
              StatusChip(
                g.minSelect > 0
                    ? 'food.pick_required'.trParams({'n': '${g.minSelect}'})
                    : 'food.pick_up_to'.trParams({'n': '${g.maxSelect}'}),
                color: g.minSelect > 0 && !satisfied ? GoColors.danger : (satisfied && g.minSelect > 0 ? GoColors.success : GoColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final o in g.options)
            _OptionRow(
              option: o,
              single: g.maxSelect == 1,
              selected: _selected[g.id]?.contains(o.id) ?? false,
              onTap: o.isAvailable ? () => _toggle(g, o) : null,
            ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.option, required this.single, required this.selected, required this.onTap});
  final AddonOption option;
  final bool single;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected ? primary.withValues(alpha: 0.10) : GoColors.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? primary : Colors.transparent, width: 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: Row(
                children: [
                  Icon(
                    single
                        ? (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked)
                        : (selected ? Icons.check_box : Icons.check_box_outline_blank),
                    color: selected ? primary : GoColors.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(option.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  if (!option.isAvailable)
                    StatusChip('food.sold_out'.tr, color: GoColors.danger)
                  else if (option.priceCentavos > 0)
                    Text('+${formatCentavos(option.priceCentavos)}', style: TextStyle(color: GoColors.muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Large, thumb-friendly quantity stepper.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.qty, required this.onChanged});
  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: GoColors.background, borderRadius: BorderRadius.circular(16)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(onPressed: qty > 1 ? () => onChanged(qty - 1) : null, icon: const Icon(Icons.remove), tooltip: '-'),
        SizedBox(
          width: 28,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(onPressed: qty < 50 ? () => onChanged(qty + 1) : null, icon: const Icon(Icons.add), tooltip: '+'),
      ],
    ),
  );
}
