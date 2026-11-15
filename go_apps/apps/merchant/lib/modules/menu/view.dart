import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class MenuView extends GetView<MerchantMenuController> {
  const MenuView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(
        title: Text('merchant.menu'.tr),
        actions: [
          IconButton(
            onPressed: c.addCategory,
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'merchant.menu.add_category'.tr,
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton.extended(
          onPressed: () => c.editItem(),
          icon: const Icon(Icons.add),
          label: Text('merchant.menu.add_item'.tr),
        ),
      ),
      body: Obx(() {
        if (c.loading.value) return const LoadingState();
        if (c.error.value != null && c.categories.isEmpty) return ErrorState(error: c.error.value!, onRetry: c.load);
        return RefreshIndicator(
          onRefresh: c.load,
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 180),
            itemCount: c.categories.length,
            onReorderItem: c.reorder,
            itemBuilder: (_, i) {
              final cat = c.categories[i];
              return Card(
                key: ValueKey(cat.id),
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  initiallyExpanded: i == 0,
                  shape: const Border(),
                  title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('merchant.items_n'.trParams({'n': '${cat.items.length}'})),
                  leading: const Icon(Icons.drag_handle),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => switch (v) {
                      'rename' => c.renameCategory(cat),
                      'add' => c.editItem(categoryId: cat.id),
                      _ => c.deleteCategory(cat),
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'add', child: Text('merchant.menu.add_item'.tr)),
                      PopupMenuItem(value: 'rename', child: Text('merchant.menu.rename'.tr)),
                      PopupMenuItem(value: 'delete', child: Text('common.delete'.tr)),
                    ],
                  ),
                  children: [
                    for (final item in cat.items)
                      ListTile(
                        leading: GoImage(item.photoUrl, width: 44, height: 44, radius: 8, icon: Icons.fastfood),
                        title: Text(item.name),
                        subtitle: Text(formatCentavos(item.priceCentavos)),
                        onTap: () => c.editItem(item: item, categoryId: cat.id),
                        trailing: Switch(value: item.isAvailable, onChanged: (v) => c.toggleItem(item, v)),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      }),
    );
  }
}
