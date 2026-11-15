import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../modules/login/binding.dart';
import '../../modules/menu/binding.dart';
import '../../modules/menu/item_editor_view.dart';
import '../../modules/not_merchant/view.dart';
import '../../modules/order/binding.dart';
import '../../modules/order/view.dart';
import '../../modules/payouts/binding.dart';
import '../../modules/payouts/view.dart';
import '../../modules/settings/binding.dart';
import '../../modules/settings/view.dart';
import '../../modules/shell/binding.dart';
import '../../modules/shell/view.dart';
import '../../modules/splash/binding.dart';
import '../../modules/splash/view.dart';
import 'app_routes.dart';

abstract class AppPages {
  static final _auth = [AuthMiddleware()];

  static final pages = <GetPage<dynamic>>[
    GetPage(name: Routes.splash, page: () => const SplashView(), binding: SplashBinding()),
    ...LoginRoutes.pages(MerchantLoginBinding()),
    GetPage(name: Routes.notMerchant, page: () => const NotMerchantView()),
    GetPage(name: Routes.home, page: () => const ShellView(), binding: ShellBinding(), middlewares: _auth),
    GetPage(name: Routes.order, page: () => const OrderView(), binding: OrderBinding(), middlewares: _auth),
    GetPage(name: Routes.itemEditor, page: () => const ItemEditorView(), binding: ItemEditorBinding(), middlewares: _auth),
    GetPage(name: Routes.settings, page: () => const SettingsView(), binding: SettingsBinding(), middlewares: _auth),
    GetPage(name: Routes.payouts, page: () => const PayoutsView(), binding: PayoutsBinding(), middlewares: _auth),
  ];
}
