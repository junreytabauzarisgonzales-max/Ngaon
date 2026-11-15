import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class ProfileView extends GetView<ProfileController> {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text('common.profile'.tr)),
      body: Obx(() {
        final p = c.session.profile.value;
        final v = p?.vehicle;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, goNavBarClearance),
          children: [
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(c.auth.user.value?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(c.auth.user.value?.phone ?? ''),
                trailing: p?.rating == null ? null : Text('★ ${p!.rating!.toStringAsFixed(1)}'),
              ),
            ),
            SectionTitle('rider.signup.vehicle'.tr),
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text('rider.vehicle.plate'.tr),
                    trailing: Text(v?.plate ?? '—', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  ListTile(title: Text('rider.vehicle.make_model'.tr), trailing: Text(v?.makeModel ?? '—')),
                  ListTile(title: Text('rider.vehicle.color'.tr), trailing: Text(v?.color ?? '—')),
                ],
              ),
            ),
            SectionTitle('rider.signup.documents'.tr),
            Card(
              child: ListTile(
                leading: Icon(
                  p?.status == RiderStatus.approved ? Icons.verified : Icons.hourglass_top,
                  color: p?.status == RiderStatus.approved ? GoColors.success : GoColors.warning,
                ),
                title: Text('rider.status.${p?.status.wire ?? 'pending_review'}'.tr),
              ),
            ),
            SectionTitle('theme.title'.tr),
            const ThemeModeSelector(),
            SectionTitle('common.language'.tr),
            Card(
              child: RadioGroup<String>(
                groupValue: c.language.value,
                onChanged: (v) => c.setLanguage(v!),
                child: Column(
                  children: [
                    RadioListTile(value: 'en', title: Text('common.english'.tr)),
                    RadioListTile(value: 'fil', title: Text('common.filipino'.tr)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(leading: const Icon(Icons.logout), title: Text('common.logout'.tr), onTap: c.logout),
            ),
          ],
        );
      }),
    );
  }
}
