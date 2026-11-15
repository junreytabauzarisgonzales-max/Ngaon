import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../home/controller.dart';
import '../home/view.dart';
import '../messages/controller.dart';
import '../messages/view.dart';
import '../orders/view.dart';
import '../scan/view.dart';
import 'controller.dart';

class ShellView extends GetView<ShellController> {
  const ShellView({super.key});

  @override
  Widget build(BuildContext context) => GoNavShell(
    index: controller.index,
    // Tapping Home again scrolls back to the top.
    onReselect: (i) {
      if (i == 0) Get.find<HomeController>().scrollToTop();
    },
    items: [
      const GoNavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, labelKey: 'nav.home'),
      const GoNavItem(icon: Icons.qr_code_scanner, activeIcon: Icons.qr_code_scanner_rounded, labelKey: 'nav.scan'),
      const GoNavItem(icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long, labelKey: 'nav.activity'),
      GoNavItem(
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble,
        labelKey: 'nav.messages',
        badge: Get.find<MessagesController>().liveCount,
      ),
    ],
    pages: const [HomeView(), ScanView(), OrdersView(), MessagesView()],
  );
}
