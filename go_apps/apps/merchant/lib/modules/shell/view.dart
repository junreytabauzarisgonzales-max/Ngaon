import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../app/services/merchant_session_service.dart';
import '../board/view.dart';
import '../menu/view.dart';
import '../profile/view.dart';
import '../sales/view.dart';
import 'controller.dart';

class ShellView extends GetView<ShellController> {
  const ShellView({super.key});

  @override
  Widget build(BuildContext context) => GoNavShell(
    index: controller.index,
    items: [
      GoNavItem(
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long,
        labelKey: 'common.orders',
        badge: Get.find<MerchantSessionService>().newCount,
      ),
      const GoNavItem(icon: Icons.restaurant_menu_outlined, activeIcon: Icons.restaurant_menu, labelKey: 'merchant.menu'),
      const GoNavItem(icon: Icons.insights_outlined, activeIcon: Icons.insights, labelKey: 'merchant.sales'),
      const GoNavItem(icon: Icons.storefront_outlined, activeIcon: Icons.storefront, labelKey: 'merchant.store'),
    ],
    pages: const [BoardView(), MenuView(), SalesView(), ProfileView()],
  );
}
