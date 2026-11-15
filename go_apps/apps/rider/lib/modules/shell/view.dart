import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../earnings/view.dart';
import '../home/view.dart';
import '../profile/view.dart';
import '../wallet/view.dart';
import 'controller.dart';

class ShellView extends GetView<ShellController> {
  const ShellView({super.key});

  @override
  Widget build(BuildContext context) => GoNavShell(
    index: controller.index,
    items: const [
      GoNavItem(icon: Icons.two_wheeler_outlined, activeIcon: Icons.two_wheeler, labelKey: 'common.home'),
      GoNavItem(icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, labelKey: 'rider.earnings'),
      GoNavItem(icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet, labelKey: 'rider.wallet'),
      GoNavItem(icon: Icons.person_outline, activeIcon: Icons.person, labelKey: 'common.profile'),
    ],
    pages: const [HomeView(), EarningsView(), WalletView(), ProfileView()],
  );
}
