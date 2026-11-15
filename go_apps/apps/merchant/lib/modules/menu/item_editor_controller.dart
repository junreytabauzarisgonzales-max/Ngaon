import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

class OptionDraft {
  OptionDraft({this.id, String name = '', int price = 0, this.available = true})
    : name = TextEditingController(text: name),
      price = TextEditingController(text: price == 0 ? '' : centavosToInput(price));
  final String? id;
  final TextEditingController name;
  final TextEditingController price;
  bool available;

  Map<String, dynamic> toJson() => {'id': id, 'name': name.text, 'price': price.text, 'available': available};
  factory OptionDraft.fromJson(Map<String, dynamic> j) => OptionDraft(
    id: j['id'] as String?,
    name: j['name'] as String? ?? '',
    price: parsePesosToCentavos(j['price'] as String? ?? '') ?? 0,
    available: j['available'] as bool? ?? true,
  );
}

class GroupDraft {
  GroupDraft({this.id, String name = '', this.min = 0, this.max = 1, List<OptionDraft>? options})
    : name = TextEditingController(text: name),
      options = options ?? [OptionDraft()];
  final String? id;
  final TextEditingController name;
  int min;
  int max;
  final List<OptionDraft> options;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name.text,
    'min': min,
    'max': max,
    'options': options.map((o) => o.toJson()).toList(),
  };
  factory GroupDraft.fromJson(Map<String, dynamic> j) => GroupDraft(
    id: j['id'] as String?,
    name: j['name'] as String? ?? '',
    min: j['min'] as int? ?? 0,
    max: j['max'] as int? ?? 1,
    options: [for (final o in (j['options'] as List? ?? const [])) OptionDraft.fromJson(Map<String, dynamic>.from(o as Map))],
  );
}

/// Create / edit a menu item with add-on groups. Edits in progress are
/// persisted so a killed app never loses them.
class ItemEditorController extends GetxController {
  final MerchantAdminRepository repo = Get.find();
  final StorageService storage = Get.find();

  MenuItem? item;
  late List<MenuCategory> categories;
  final categoryId = ''.obs;
  final name = TextEditingController();
  final description = TextEditingController();
  final price = TextEditingController();
  final available = true.obs;
  final groups = <GroupDraft>[].obs;
  String? photoKey;
  final saving = false.obs;
  final priceError = RxnString();

  String get draftKey => 'menu_item_${item?.id ?? 'new'}';

  @override
  void onInit() {
    super.onInit();
    final (MenuItem? i, String cat, List<MenuCategory> cats) = Get.arguments as (MenuItem?, String, List<MenuCategory>);
    item = i;
    categories = cats;
    categoryId.value = i?.categoryId ?? cat;
    final draft = storage.readDraft(draftKey);
    if (draft != null) {
      _fromDraft(draft);
      Future<void>.delayed(const Duration(milliseconds: 300), () => GoErrors.toast('common.draft_restored'.tr));
    } else if (i != null) {
      name.text = i.name;
      description.text = i.description ?? '';
      price.text = centavosToInput(i.priceCentavos);
      available.value = i.isAvailable;
      groups.assignAll([
        for (final g in i.addonGroups)
          GroupDraft(
            id: g.id,
            name: g.name,
            min: g.minSelect,
            max: g.maxSelect,
            options: [for (final o in g.options) OptionDraft(id: o.id, name: o.name, price: o.priceCentavos, available: o.isAvailable)],
          ),
      ]);
    }
  }

  void _fromDraft(Map<String, dynamic> d) {
    categoryId.value = d['category_id'] as String? ?? categoryId.value;
    name.text = d['name'] as String? ?? '';
    description.text = d['description'] as String? ?? '';
    price.text = d['price'] as String? ?? '';
    available.value = d['available'] as bool? ?? true;
    photoKey = d['photo_key'] as String?;
    groups.assignAll([for (final g in (d['groups'] as List? ?? const [])) GroupDraft.fromJson(Map<String, dynamic>.from(g as Map))]);
  }

  void saveDraft() => storage.writeDraft(draftKey, {
    'category_id': categoryId.value,
    'name': name.text,
    'description': description.text,
    'price': price.text,
    'available': available.value,
    'photo_key': photoKey,
    'groups': groups.map((g) => g.toJson()).toList(),
  });

  void addGroup() {
    groups.add(GroupDraft());
    saveDraft();
  }

  void removeGroup(GroupDraft g) {
    groups.remove(g);
    saveDraft();
  }

  void touch() {
    groups.refresh();
    saveDraft();
  }

  Future<void> save() async {
    final p = parsePesosToCentavos(price.text);
    priceError.value = p == null ? 'merchant.menu.price_invalid'.tr : null;
    if (name.text.trim().isEmpty || p == null) return;
    final input = MenuItemInput(
      categoryId: categoryId.value,
      name: name.text.trim(),
      description: description.text.trim().isEmpty ? null : description.text.trim(),
      photoKey: photoKey,
      priceCentavos: p,
      isAvailable: available.value,
      addonGroups: [
        for (final g in groups)
          if (g.name.text.trim().isNotEmpty)
            AddonGroupInput(
              id: g.id,
              name: g.name.text.trim(),
              minSelect: g.min,
              maxSelect: g.max < g.min ? g.min : g.max,
              options: [
                for (final o in g.options)
                  if (o.name.text.trim().isNotEmpty)
                    AddonOptionInput(
                      id: o.id,
                      name: o.name.text.trim(),
                      priceCentavos: parsePesosToCentavos(o.price.text) ?? 0,
                      isAvailable: o.available,
                    ),
              ],
            ),
      ],
    );
    saving.value = true;
    try {
      item == null ? await repo.createItem(input) : await repo.updateItem(item!.id, input);
      await storage.clearDraft(draftKey);
      Get.back();
      GoErrors.toast('common.saved'.tr);
    } catch (e) {
      GoErrors.show(e);
    } finally {
      saving.value = false;
    }
  }

  Future<void> delete() async {
    if (item == null || !await confirmDialog(title: 'dialog.are_you_sure'.tr, danger: true, confirmText: 'common.delete'.tr)) return;
    final ok = await GoErrors.guard(() async {
      await repo.deleteItem(item!.id);
      return true;
    });
    if (ok == true) {
      await storage.clearDraft(draftKey);
      Get.back();
    }
  }

  Future<void> discardDraft() async {
    await storage.clearDraft(draftKey);
    Get.back();
  }
}
