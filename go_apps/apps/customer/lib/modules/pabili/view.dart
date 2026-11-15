import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/widgets/stop_field.dart';
import 'controller.dart';

class PabiliView extends GetView<PabiliController> {
  const PabiliView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text('service.pabili'.tr)),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          Text('pabili.intro'.tr, style: TextStyle(color: GoColors.muted)),
          const SizedBox(height: 12),
          TextField(
            controller: c.store,
            decoration: InputDecoration(labelText: 'pabili.store'.tr, hintText: 'pabili.store_hint'.tr),
          ),
          const SizedBox(height: 8),
          Obx(
            () => StopField(
              label: 'pabili.store_pin'.tr,
              stop: c.storePin.value,
              icon: Icons.storefront,
              onPicked: (s) {
                c.storePin.value = s;
                c.save();
              },
            ),
          ),
          SectionTitle(
            'pabili.list'.tr,
            trailing: TextButton.icon(onPressed: c.addRow, icon: const Icon(Icons.add), label: Text('common.add'.tr)),
          ),
          Obx(
            () => Column(
              children: [
                for (final r in c.rows)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: r.name,
                                  decoration: InputDecoration(hintText: 'pabili.item'.tr),
                                ),
                              ),
                              IconButton(onPressed: () => r.qty.value > 1 ? r.qty.value-- : null, icon: const Icon(Icons.remove)),
                              Obx(() => Text('${r.qty.value}', style: const TextStyle(fontWeight: FontWeight.w700))),
                              IconButton(onPressed: () => r.qty.value++, icon: const Icon(Icons.add)),
                              if (c.rows.length > 1) IconButton(onPressed: () => c.removeRow(r), icon: const Icon(Icons.close)),
                            ],
                          ),
                          TextField(
                            controller: r.note,
                            decoration: InputDecoration(hintText: 'pabili.item_note'.tr, isDense: true),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Obx(
            () => TextField(
              controller: c.budget,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'pabili.budget'.tr,
                helperText: 'pabili.budget_help'.tr,
                helperMaxLines: 2,
                prefixText: '₱ ',
                errorText: c.budgetError.value,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Obx(
            () => StopField(
              label: 'common.dropoff'.tr,
              stop: c.dropoff.value,
              color: GoColors.danger,
              onPicked: (s) {
                c.dropoff.value = s;
                c.save();
              },
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: c.next, child: Text('ride.see_price'.tr)),
        ),
      ),
    );
  }
}
