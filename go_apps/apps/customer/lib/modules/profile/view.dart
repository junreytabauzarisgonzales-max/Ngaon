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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Card(
            child: Obx(
              () => ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(c.auth.user.value?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(c.auth.user.value?.phone ?? ''),
                trailing: const Icon(Icons.edit),
                onTap: c.editName,
              ),
            ),
          ),
          SectionTitle(
            'picker.saved'.tr,
            trailing: IconButton(onPressed: c.addPlace, icon: const Icon(Icons.add)),
          ),
          Obx(
            () => Card(
              child: Column(
                children: [
                  if (c.places.isEmpty) ListTile(title: Text('common.empty'.tr)),
                  for (final p in c.places)
                    ListTile(
                      leading: const Icon(Icons.bookmark_outline),
                      title: Text(p.label),
                      subtitle: Text(p.address),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => c.deletePlace(p)),
                    ),
                ],
              ),
            ),
          ),
          SectionTitle('theme.title'.tr),
          const ThemeModeSelector(),
          SectionTitle('common.language'.tr),
          Card(
            child: Obx(
              () => RadioGroup<String>(
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
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(leading: const Icon(Icons.logout), title: Text('common.logout'.tr), onTap: c.logout),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: GoColors.danger),
                  title: Text('profile.delete'.tr, style: const TextStyle(color: GoColors.danger)),
                  onTap: c.deleteAccount,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
