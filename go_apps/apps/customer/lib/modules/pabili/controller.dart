import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';
import '../checkout/controller.dart';

class PabiliRow {
  PabiliRow({String name = '', int qty = 1, String note = ''})
    : name = TextEditingController(text: name),
      note = TextEditingController(text: note),
      qty = qty.obs;
  final TextEditingController name;
  final TextEditingController note;
  final RxInt qty;
}

/// Shopping list form. Draft persisted with get_storage.
class PabiliController extends GetxController {
  final StorageService storage = Get.find();
  static const draftKey = 'pabili';

  final store = TextEditingController();
  final budget = TextEditingController();
  final storePin = Rxn<Stop>();
  final dropoff = Rxn<Stop>();
  final rows = <PabiliRow>[].obs;
  final budgetError = RxnString();

  @override
  void onInit() {
    super.onInit();
    final d = storage.readDraft(draftKey);
    if (d != null) {
      store.text = d['store'] as String? ?? '';
      budget.text = d['budget'] as String? ?? '';
      if (d['pin'] != null) storePin.value = Stop.fromJson(Map<String, dynamic>.from(d['pin'] as Map));
      if (d['dropoff'] != null) dropoff.value = Stop.fromJson(Map<String, dynamic>.from(d['dropoff'] as Map));
      for (final r in (d['rows'] as List? ?? const [])) {
        rows.add(PabiliRow(name: r['name'] as String, qty: r['qty'] as int, note: r['note'] as String? ?? ''));
      }
    }
    if (rows.isEmpty) rows.add(PabiliRow());
    for (final c in [store, budget]) {
      c.addListener(save);
    }
    for (final r in rows) {
      _listen(r);
    }
  }

  void _listen(PabiliRow r) {
    r.name.addListener(save);
    r.note.addListener(save);
    ever(r.qty, (_) => save());
  }

  void addRow() {
    final r = PabiliRow();
    _listen(r);
    rows.add(r);
    save();
  }

  void removeRow(PabiliRow r) {
    rows.remove(r);
    save();
  }

  void save() => storage.writeDraft(draftKey, {
    'store': store.text,
    'budget': budget.text,
    'pin': storePin.value?.toJson(),
    'dropoff': dropoff.value?.toJson(),
    'rows': [
      for (final r in rows) {'name': r.name.text, 'qty': r.qty.value, 'note': r.note.text},
    ],
  });

  List<PabiliItem> get items => [
    for (final r in rows)
      if (r.name.text.trim().isNotEmpty)
        PabiliItem(name: r.name.text.trim(), quantity: r.qty.value, note: r.note.text.trim().isEmpty ? null : r.note.text.trim()),
  ];

  void next() {
    final b = parsePesosToCentavos(budget.text);
    budgetError.value = b == null || b <= 0 ? 'pabili.budget_invalid'.tr : null;
    if (store.text.trim().isEmpty || items.isEmpty || dropoff.value == null || b == null || b <= 0) {
      if (budgetError.value == null) GoErrors.toast('pabili.fill_all'.tr);
      return;
    }
    // Without a pin the rider shops near the drop-off (see API_CONTRACT.md).
    final pickup = storePin.value ?? Stop(address: store.text.trim(), location: dropoff.value!.location);
    Get.toNamed(
      Routes.checkout,
      arguments: CheckoutArgs(
        title: 'service.pabili'.tr,
        request: QuoteRequest(
          service: ServiceType.pabili,
          pickup: Stop(address: storePin.value?.address ?? store.text.trim(), location: pickup.location, contactName: store.text.trim()),
          dropoff: dropoff.value!,
          pabili: PabiliQuoteInput(storeName: store.text.trim(), items: items, estimatedItemTotalCentavos: b),
        ),
        onPlaced: () => storage.clearDraft(draftKey),
      ),
    );
  }
}
