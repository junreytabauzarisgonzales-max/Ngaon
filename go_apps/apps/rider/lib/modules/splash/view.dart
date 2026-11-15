import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class SplashView extends GetView<SplashController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: GoColors.night,
    body: Obx(
      () => controller.error.value == null
          ? const Center(
              child: Text(
                'Go Rider',
                style: TextStyle(color: GoColors.accent, fontSize: 44, fontWeight: FontWeight.w900),
              ),
            )
          : Container(
              color: GoColors.background,
              child: ErrorState(error: controller.error.value!, onRetry: controller.route),
            ),
    ),
  );
}
