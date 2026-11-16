import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class SplashView extends GetView<SplashController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: GoColors.primary,
    body: Center(
      child: Text(
        'Ngaon',
        style: TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w900),
      ),
    ),
  );
}

class OnboardingView extends GetView<SplashController> {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            const Icon(Icons.location_on, size: 96, color: GoColors.primary),
            const SizedBox(height: 24),
            Text(
              'onboarding.title'.tr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'onboarding.body'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: GoColors.muted),
            ),
            const Spacer(),
            Obx(
              () => FilledButton(
                onPressed: controller.requesting.value ? null : controller.allowLocation,
                child: Text('onboarding.allow'.tr),
              ),
            ),
            TextButton(onPressed: controller.skip, child: Text('onboarding.later'.tr)),
          ],
        ),
      ),
    ),
  );
}
