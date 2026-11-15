import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'item_editor_controller.dart';

class ItemEditorView extends GetView<ItemEditorController> {
  const ItemEditorView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.item == null ? 'merchant.menu.add_item'.tr : 'merchant.menu.edit_item'.tr),
        actions: [
          IconButton(onPressed: c.discardDraft, icon: const Icon(Icons.undo), tooltip: 'merchant.menu.discard'.tr),
          if (c.item != null) IconButton(onPressed: c.delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PhotoUploadTile(
            purpose: UploadPurpose.menuItemPhoto,
            label: 'merchant.menu.photo'.tr,
            initialKey: c.photoKey,
            onUploaded: (k) {
              c.photoKey = k;
              c.saveDraft();
            },
          ),
          const SizedBox(height: 12),
          Obx(
            () => DropdownButtonFormField<String>(
              initialValue: c.categoryId.value,
              decoration: InputDecoration(labelText: 'merchant.menu.category'.tr),
              items: [for (final cat in c.categories) DropdownMenuItem(value: cat.id, child: Text(cat.name))],
              onChanged: (v) {
                c.categoryId.value = v!;
                c.saveDraft();
              },
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c.name,
            onChanged: (_) => c.saveDraft(),
            decoration: InputDecoration(labelText: 'merchant.menu.name'.tr),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c.description,
            onChanged: (_) => c.saveDraft(),
            maxLines: 2,
            decoration: InputDecoration(labelText: 'merchant.menu.description'.tr),
          ),
          const SizedBox(height: 12),
          Obx(
            () => TextField(
              controller: c.price,
              onChanged: (_) => c.saveDraft(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'merchant.menu.price'.tr, prefixText: '₱ ', errorText: c.priceError.value),
            ),
          ),
          Obx(
            () => SwitchListTile(
              title: Text('merchant.available'.tr),
              value: c.available.value,
              onChanged: (v) {
                c.available.value = v;
                c.saveDraft();
              },
            ),
          ),
          SectionTitle(
            'merchant.menu.addons'.tr,
            trailing: TextButton.icon(onPressed: c.addGroup, icon: const Icon(Icons.add), label: Text('common.add'.tr)),
          ),
          Obx(
            () => Column(
              children: [for (final g in c.groups) _GroupEditor(group: g, controller: c)],
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Obx(() => FilledButton(onPressed: c.saving.value ? null : c.save, child: Text('common.save'.tr))),
        ),
      ),
    );
  }
}

class _GroupEditor extends StatelessWidget {
  const _GroupEditor({required this.group, required this.controller});
  final GroupDraft group;
  final ItemEditorController controller;

  @override
  Widget build(BuildContext context) {
    final g = group, c = controller;
    Widget counter(String label, int value, ValueChanged<int> set) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        IconButton(onPressed: value > 0 ? () => set(value - 1) : null, icon: const Icon(Icons.remove, size: 18)),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(onPressed: value < g.options.length ? () => set(value + 1) : null, icon: const Icon(Icons.add, size: 18)),
      ],
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: g.name,
                    onChanged: (_) => c.saveDraft(),
                    decoration: InputDecoration(labelText: 'merchant.menu.group_name'.tr),
                  ),
                ),
                IconButton(onPressed: () => c.removeGroup(g), icon: const Icon(Icons.close)),
              ],
            ),
            Wrap(
              children: [
                counter('merchant.menu.min'.tr, g.min, (v) {
                  g.min = v;
                  if (g.max < v) g.max = v;
                  c.touch();
                }),
                counter('merchant.menu.max'.tr, g.max, (v) {
                  g.max = v < 1 ? 1 : v;
                  if (g.min > g.max) g.min = g.max;
                  c.touch();
                }),
              ],
            ),
            for (final o in g.options)
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: o.name,
                      onChanged: (_) => c.saveDraft(),
                      decoration: InputDecoration(hintText: 'merchant.menu.option'.tr, isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: o.price,
                      onChanged: (_) => c.saveDraft(),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(prefixText: '+₱ ', isDense: true),
                    ),
                  ),
                  Switch(
                    value: o.available,
                    onChanged: (v) {
                      o.available = v;
                      c.touch();
                    },
                  ),
                  IconButton(
                    onPressed: g.options.length > 1
                        ? () {
                            g.options.remove(o);
                            c.touch();
                          }
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  g.options.add(OptionDraft());
                  c.touch();
                },
                icon: const Icon(Icons.add),
                label: Text('merchant.menu.add_option'.tr),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
