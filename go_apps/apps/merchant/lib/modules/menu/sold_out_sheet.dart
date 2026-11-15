import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

/// One-tap "Sold out" toggles for items and add-on options, from the board.
class SoldOutSheet extends StatefulWidget {
  const SoldOutSheet({super.key});
  @override
  State<SoldOutSheet> createState() => _SoldOutSheetState();
}

class _SoldOutSheetState extends State<SoldOutSheet> {
  final repo = Get.find<MerchantAdminRepository>();
  List<MenuCategory>? _menu;
  final _optionState = <String, bool>{};
  final _itemState = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await GoErrors.guard(repo.menu);
    if (mounted && m != null) setState(() => _menu = m);
  }

  Future<void> _item(MenuItem i, bool soldOut) async {
    setState(() => _itemState[i.id] = !soldOut);
    if (await GoErrors.guard(() => repo.setItemAvailability(i.id, !soldOut)) == null) setState(() => _itemState.remove(i.id));
  }

  Future<void> _option(AddonOption o, bool soldOut) async {
    setState(() => _optionState[o.id] = !soldOut);
    final ok = await GoErrors.guard(() async {
      await repo.setOptionAvailability(o.id, !soldOut);
      return true;
    });
    if (ok != true) setState(() => _optionState.remove(o.id));
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (_) {
      final menu = _menu;
      if (menu == null) return const LoadingState();
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('merchant.sold_out_hint'.tr, style: TextStyle(color: GoColors.muted)),
          for (final c in menu) ...[
            SectionTitle(c.name),
            for (final i in c.items) ...[
              SwitchListTile(
                key: Key('soldout.${i.name}'),
                contentPadding: EdgeInsets.zero,
                title: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text((_itemState[i.id] ?? i.isAvailable) ? 'merchant.available'.tr : 'merchant.sold_out_label'.tr),
                value: !(_itemState[i.id] ?? i.isAvailable),
                activeThumbColor: GoColors.danger,
                onChanged: (v) => _item(i, v),
              ),
              for (final g in i.addonGroups)
                for (final o in g.options)
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${g.name}: ${o.name}'),
                      value: !(_optionState[o.id] ?? o.isAvailable),
                      activeThumbColor: GoColors.danger,
                      onChanged: (v) => _option(o, v),
                    ),
                  ),
            ],
          ],
        ],
      );
    },
  );
}
