import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/routes/app_routes.dart';

class MerchantMenuController extends GetxController {
  final MerchantAdminRepository repo = Get.find();
  final categories = <MenuCategory>[].obs;
  final loading = false.obs;
  final error = Rxn<Object>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = categories.isEmpty;
    error.value = null;
    try {
      final c = await repo.menu();
      c.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      categories.assignAll(c);
    } catch (e) {
      error.value = e;
    } finally {
      loading.value = false;
    }
  }

  Future<String?> _askName(String title, [String initial = '']) {
    final ctrl = TextEditingController(text: initial);
    return Get.dialog<String>(
      AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: Get.back, child: Text('common.cancel'.tr)),
          TextButton(
            onPressed: () => Get.back(result: ctrl.text.trim()),
            child: Text('common.save'.tr),
          ),
        ],
      ),
    );
  }

  Future<void> addCategory() async {
    final n = await _askName('merchant.menu.add_category'.tr);
    if (n == null || n.isEmpty) return;
    if (await GoErrors.guard(() => repo.addCategory(n)) != null) await load();
  }

  Future<void> renameCategory(MenuCategory c) async {
    final n = await _askName('merchant.menu.rename'.tr, c.name);
    if (n == null || n.isEmpty) return;
    if (await GoErrors.guard(() => repo.renameCategory(c.id, n)) != null) await load();
  }

  Future<void> deleteCategory(MenuCategory c) async {
    if (c.items.isNotEmpty) {
      GoErrors.toast('merchant.menu.not_empty'.tr);
      return;
    }
    if (!await confirmDialog(title: 'dialog.are_you_sure'.tr, danger: true, confirmText: 'common.delete'.tr)) return;
    final ok = await GoErrors.guard(() async {
      await repo.deleteCategory(c.id);
      return true;
    });
    if (ok == true) await load();
  }

  /// `newIndex` is already adjusted for the removed item (onReorderItem).
  Future<void> reorder(int oldIndex, int newIndex) async {
    final c = categories.removeAt(oldIndex);
    categories.insert(newIndex, c);
    await GoErrors.guard(() => repo.reorderCategories(categories.map((c) => c.id).toList()));
  }

  Future<void> toggleItem(MenuItem i, bool available) async {
    final updated = await GoErrors.guard(() => repo.setItemAvailability(i.id, available));
    if (updated != null) await load();
  }

  Future<void> editItem({MenuItem? item, String? categoryId}) async {
    if (categories.isEmpty) return addCategory();
    await Get.toNamed(Routes.itemEditor, arguments: (item, categoryId ?? categories.first.id, categories.toList()));
    await load();
  }
}
