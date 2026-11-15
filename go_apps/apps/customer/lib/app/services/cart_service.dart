import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

class CartLine {
  CartLine({
    required this.itemId,
    required this.name,
    required this.unitCentavos,
    required this.quantity,
    required this.addonOptionIds,
    required this.addonNames,
    this.note,
  });

  final String itemId;
  final String name;
  final int unitCentavos;
  int quantity;
  final List<String> addonOptionIds;
  final List<String> addonNames;
  final String? note;

  int get totalCentavos => unitCentavos * quantity;

  Map<String, dynamic> toJson() => {
    'item_id': itemId,
    'name': name,
    'unit_centavos': unitCentavos,
    'quantity': quantity,
    'addon_option_ids': addonOptionIds,
    'addon_names': addonNames,
    'note': note,
  };

  factory CartLine.fromJson(Map<String, dynamic> j) => CartLine(
    itemId: j['item_id'] as String,
    name: j['name'] as String,
    unitCentavos: j['unit_centavos'] as int,
    quantity: j['quantity'] as int,
    addonOptionIds: (j['addon_option_ids'] as List).cast<String>(),
    addonNames: (j['addon_names'] as List).cast<String>(),
    note: j['note'] as String?,
  );

  FoodQuoteItem toQuote() => FoodQuoteItem(itemId: itemId, quantity: quantity, addonOptionIds: addonOptionIds, note: note);
}

/// Single-merchant cart, persisted so it survives app kills.
class CartService extends GetxService {
  final StorageService _storage = Get.find();
  static const _key = 'cart';

  final merchantId = RxnString();
  final merchantName = ''.obs;
  final minOrderCentavos = 0.obs;
  final lines = <CartLine>[].obs;

  int get subtotal => lines.fold(0, (s, l) => s + l.totalCentavos);
  int get count => lines.fold(0, (s, l) => s + l.quantity);
  bool get isEmpty => lines.isEmpty;

  @override
  void onInit() {
    super.onInit();
    final d = _storage.readDraft(_key);
    if (d != null) {
      merchantId.value = d['merchant_id'] as String?;
      merchantName.value = (d['merchant_name'] as String?) ?? '';
      minOrderCentavos.value = (d['min_order'] as int?) ?? 0;
      lines.assignAll(((d['lines'] as List?) ?? const []).map((e) => CartLine.fromJson(Map<String, dynamic>.from(e as Map))));
    }
  }

  bool belongsToOther(String id) => merchantId.value != null && merchantId.value != id && lines.isNotEmpty;

  void add(Merchant m, CartLine line) {
    if (merchantId.value != m.id) {
      lines.clear();
      merchantId.value = m.id;
    }
    merchantName.value = m.name;
    minOrderCentavos.value = m.minOrderCentavos;
    lines.add(line);
    _save();
  }

  void changeQty(CartLine line, int delta) {
    line.quantity += delta;
    if (line.quantity <= 0) lines.remove(line);
    lines.refresh();
    _save();
  }

  void clear() {
    lines.clear();
    merchantId.value = null;
    _storage.clearDraft(_key);
  }

  void _save() => _storage.writeDraft(_key, {
    'merchant_id': merchantId.value,
    'merchant_name': merchantName.value,
    'min_order': minOrderCentavos.value,
    'lines': lines.map((l) => l.toJson()).toList(),
  });
}
