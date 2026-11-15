import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

class NotMerchantView extends StatelessWidget {
  const NotMerchantView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Icon(Icons.store_mall_directory_outlined, size: 88, color: GoColors.muted),
            const SizedBox(height: 16),
            Text(
              'merchant.not_merchant'.tr,
              key: const Key('not_merchant'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            FilledButton(onPressed: () => Get.find<AuthService>().logout(), child: Text('login.change_number'.tr)),
          ],
        ),
      ),
    ),
  );
}
