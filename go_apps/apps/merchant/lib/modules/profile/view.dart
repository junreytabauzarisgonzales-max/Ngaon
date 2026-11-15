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
      appBar: AppBar(title: Text('merchant.store'.tr)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, goNavBarClearance),
        children: [
          Obx(() {
            final a = c.session.account.value;
            final m = c.session.store.value;
            return Card(
              child: ListTile(
                leading: GoImage(m?.logoUrl, width: 48, height: 48, radius: 24, icon: Icons.storefront),
                title: Text(m?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${a?.staffName ?? ''} · ${'merchant.role.${a?.role.name ?? 'staff'}'.tr}'),
              ),
            );
          }),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: Text('merchant.settings'.tr),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: c.openSettings,
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance),
                  title: Text('merchant.payouts'.tr),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: c.openPayouts,
                ),
              ],
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
            child: ListTile(leading: const Icon(Icons.logout), title: Text('common.logout'.tr), onTap: c.logout),
          ),
        ],
      ),
    );
  }
}
