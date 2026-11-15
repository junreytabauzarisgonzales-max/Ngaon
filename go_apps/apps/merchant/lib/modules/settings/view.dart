import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final m = c.session.store.value!;
    return Scaffold(
      appBar: AppBar(title: Text('merchant.settings'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: PhotoUploadTile(purpose: UploadPurpose.merchantLogo, label: 'merchant.logo'.tr, onUploaded: (k) => c.logoKey = k),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: PhotoUploadTile(purpose: UploadPurpose.merchantCover, label: 'merchant.cover'.tr, onUploaded: (k) => c.coverKey = k),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c.name,
            decoration: InputDecoration(labelText: 'merchant.store_name'.tr),
          ),
          const SizedBox(height: 12),
          TextField(
            enabled: false,
            controller: TextEditingController(text: m.address),
            decoration: InputDecoration(labelText: 'merchant.address'.tr, helperText: 'merchant.address_help'.tr),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c.minOrder,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'merchant.min_order'.tr, prefixText: '₱ '),
          ),
          const SizedBox(height: 12),
          Obx(
            () => Row(
              children: [
                Expanded(child: Text('merchant.default_prep'.trParams({'m': '${c.prep.value}'}))),
                Expanded(
                  child: Slider(value: c.prep.value.toDouble(), min: 5, max: 60, divisions: 11, onChanged: (v) => c.prep.value = v.round()),
                ),
              ],
            ),
          ),
          SectionTitle('merchant.hours'.tr),
          Obx(
            () => Card(
              child: Column(
                children: [
                  for (final d in c.days)
                    ListTile(
                      dense: true,
                      leading: Switch(
                        value: d.open,
                        onChanged: (v) {
                          d.open = v;
                          c.days.refresh();
                        },
                      ),
                      title: Text('merchant.weekday.${d.weekday}'.tr, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: d.open
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(onPressed: () => c.pickTime(d, true), child: Text(d.opens)),
                                const Text('–'),
                                TextButton(onPressed: () => c.pickTime(d, false), child: Text(d.closes)),
                              ],
                            )
                          : Text('merchant.closed'.tr),
                    ),
                ],
              ),
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
