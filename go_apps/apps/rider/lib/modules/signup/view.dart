import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class SignupView extends GetView<SignupController> {
  const SignupView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final labels = {
      UploadPurpose.riderLicense: 'rider.doc.license'.tr,
      UploadPurpose.riderOrcr: 'rider.doc.orcr'.tr,
      UploadPurpose.riderSelfie: 'rider.doc.selfie'.tr,
      UploadPurpose.riderClearance: 'rider.doc.clearance'.tr,
    };
    return Scaffold(
      appBar: AppBar(title: Text('rider.signup.title'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('rider.signup.intro'.tr, style: TextStyle(color: GoColors.muted)),
          SectionTitle('rider.signup.personal'.tr),
          TextField(
            controller: c.name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'login.name_label'.tr),
          ),
          SectionTitle('rider.signup.vehicle'.tr),
          TextField(
            controller: c.plate,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: 'rider.vehicle.plate'.tr),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: c.makeModel,
            decoration: InputDecoration(labelText: 'rider.vehicle.make_model'.tr, hintText: 'Honda Click 125i'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: c.color,
            decoration: InputDecoration(labelText: 'rider.vehicle.color'.tr),
          ),
          SectionTitle('rider.signup.documents'.tr),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
            children: [
              for (final p in SignupController.required)
                PhotoUploadTile(
                  purpose: p,
                  label: labels[p]!,
                  initialKey: c.docs[p],
                  allowGallery: p != UploadPurpose.riderSelfie,
                  onUploaded: (k) => c.setDoc(p, k),
                ),
            ],
          ),
          const SizedBox(height: 100),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Obx(
            () => FilledButton(
              onPressed: c.submitting.value ? null : c.submit,
              child: Text('rider.signup.submit'.trParams({'n': '${c.docs.length}'})),
            ),
          ),
        ),
      ),
    );
  }
}
