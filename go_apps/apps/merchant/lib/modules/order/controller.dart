import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/merchant_session_service.dart';

class OrderController extends GetxController {
  final MerchantSessionService session = Get.find();
  final MerchantAdminRepository repo = Get.find();
  late final String id;
  final order = Rxn<MerchantOrder>();
  final busy = false.obs;
  final error = Rxn<Object>();
  final List<Worker> _workers = [];

  @override
  void onInit() {
    super.onInit();
    id = Get.arguments as String;
    order.value = session.find(id);
    for (final l in [session.newOrders, session.preparing, session.ready, session.done]) {
      _workers.add(
        ever(l, (_) {
          final o = session.find(id);
          if (o != null) order.value = o;
        }),
      );
    }
    load();
  }

  Future<void> load() async {
    try {
      order.value = await repo.order(id);
    } catch (e) {
      if (order.value == null) error.value = e;
    }
  }

  Future<void> accept() async {
    final o = order.value!;
    final prep = await showGoSheet<int>(
      title: 'merchant.prep_time'.tr,
      child: PrepTimeSheet(initial: o.prepTimeMinutes ?? session.store.value?.prepTimeMinutes ?? 15),
    );
    if (prep == null) return;
    busy.value = true;
    if (await session.accept(o, prep)) await load();
    busy.value = false;
  }

  Future<void> reject() async {
    final r = await showGoSheet<(RejectReason, String?)>(title: 'merchant.reject_why'.tr, child: const RejectSheet());
    if (r == null) return;
    busy.value = true;
    if (await session.reject(order.value!, r.$1, r.$2)) Get.back();
    busy.value = false;
  }

  Future<void> markReady() async {
    busy.value = true;
    if (await session.markReady(order.value!)) await load();
    busy.value = false;
  }

  @override
  void onClose() {
    for (final w in _workers) {
      w.dispose();
    }
    super.onClose();
  }
}

/// 5–60 minute picker.
class PrepTimeSheet extends StatefulWidget {
  const PrepTimeSheet({super.key, required this.initial});
  final int initial;
  @override
  State<PrepTimeSheet> createState() => _PrepTimeSheetState();
}

class _PrepTimeSheetState extends State<PrepTimeSheet> {
  late int _m = widget.initial.clamp(5, 60);
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Padding(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$_m ${'common.min'.tr}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
          ),
          Slider(value: _m.toDouble(), min: 5, max: 60, divisions: 11, label: '$_m', onChanged: (v) => setState(() => _m = v.round())),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final q in const [10, 15, 20, 30, 45])
                ChoiceChip(label: Text('$q'), selected: _m == q, onSelected: (_) => setState(() => _m = q)),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('prep.confirm'),
            onPressed: () => Get.back(result: _m),
            child: Text('merchant.accept_order'.tr),
          ),
        ],
      ),
    ),
  );
}

class RejectSheet extends StatefulWidget {
  const RejectSheet({super.key});
  @override
  State<RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<RejectSheet> {
  RejectReason _r = RejectReason.outOfStock;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<RejectReason>(
          groupValue: _r,
          onChanged: (v) => setState(() => _r = v!),
          child: Column(
            children: [for (final r in RejectReason.values) RadioListTile(value: r, title: Text('merchant.reject.${r.wire}'.tr))],
          ),
        ),
        TextField(
          controller: _note,
          decoration: InputDecoration(labelText: '${'common.notes'.tr} (${'common.optional'.tr})'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('reject.confirm'),
          style: FilledButton.styleFrom(backgroundColor: GoColors.danger),
          onPressed: () => Get.back(result: (_r, _note.text.trim().isEmpty ? null : _note.text.trim())),
          child: Text('merchant.reject_order'.tr),
        ),
      ],
    ),
  );
}
