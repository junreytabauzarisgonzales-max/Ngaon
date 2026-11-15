import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import 'controller.dart';

class SplashView extends GetView<SplashController> {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: GoColors.food,
    body: Obx(
      () => controller.error.value == null
          ? const Center(
              child: Text(
                'Go Merchant',
                style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900),
              ),
            )
          : Container(
              color: GoColors.background,
              child: ErrorState(error: controller.error.value!, onRetry: controller.route),
            ),
    ),
  );
}
