import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/widgets/stop_field.dart';
import 'controller.dart';

class PadalaView extends GetView<PadalaController> {
  const PadalaView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text('service.padala'.tr)),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          Obx(
            () => StopField(
              label: 'common.pickup'.tr,
              stop: c.pickup.value,
              icon: Icons.trip_origin,
              onPicked: (s) {
                c.pickup.value = s;
                c.save();
              },
            ),
          ),
          const SizedBox(height: 8),
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
          SectionTitle('padala.recipient'.tr),
          TextField(
            controller: c.recipientName,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'padala.recipient_name'.tr),
          ),
          const SizedBox(height: 8),
          Obx(
            () => TextField(
              controller: c.recipientPhone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'padala.recipient_phone'.tr, prefixText: '+63 ', errorText: c.phoneError.value),
            ),
          ),
          SectionTitle('padala.size_title'.tr),
          Obx(
            () => RadioGroup<PadalaSize>(
              groupValue: c.size.value,
              onChanged: (v) => c.size.value = v!,
              child: Column(
                children: [
                  for (final s in PadalaSize.values)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: RadioListTile<PadalaSize>(
                        value: s,
                        title: Text('padala.size.${s.name}'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('padala.size_desc.${s.name}'.tr),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: c.description,
            decoration: InputDecoration(labelText: 'padala.description'.tr, hintText: 'padala.description_hint'.tr),
          ),
          const SizedBox(height: 12),
          PhotoUploadTile(purpose: UploadPurpose.parcelPhoto, label: 'padala.photo'.tr, onUploaded: (k) => c.photoKey.value = k),
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
