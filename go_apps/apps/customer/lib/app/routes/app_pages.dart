import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../modules/checkout/binding.dart';
import '../../modules/checkout/view.dart';
import '../../modules/food/binding.dart';
import '../../modules/food/cart_view.dart';
import '../../modules/food/menu_view.dart';
import '../../modules/food/view.dart';
import '../../modules/login/binding.dart';
import '../../modules/pabili/binding.dart';
import '../../modules/profile/binding.dart';
import '../../modules/profile/view.dart';
import '../../modules/pabili/view.dart';
import '../../modules/padala/binding.dart';
import '../../modules/padala/view.dart';
import '../../modules/rating/binding.dart';
import '../../modules/rating/view.dart';
import '../../modules/ride/binding.dart';
import '../../modules/ride/view.dart';
import '../../modules/shell/binding.dart';
import '../../modules/shell/view.dart';
import '../../modules/splash/binding.dart';
import '../../modules/splash/view.dart';
import '../../modules/tracking/binding.dart';
import '../../modules/tracking/view.dart';
import 'app_routes.dart';

abstract class AppPages {
  static final _auth = [AuthMiddleware()];

  static final pages = <GetPage<dynamic>>[
    GetPage(name: Routes.splash, page: () => const SplashView(), binding: SplashBinding()),
    GetPage(name: Routes.onboarding, page: () => const OnboardingView(), binding: SplashBinding()),
    ...LoginRoutes.pages(CustomerLoginBinding()),
    GetPage(name: Routes.home, page: () => const ShellView(), binding: ShellBinding(), middlewares: _auth),
    GetPage(name: Routes.ride, page: () => const RideView(), binding: RideBinding(), middlewares: _auth),
    GetPage(name: Routes.food, page: () => const FoodView(), binding: FoodBinding(), middlewares: _auth),
    GetPage(name: Routes.merchant, page: () => const MenuView(), binding: MenuBinding(), middlewares: _auth),
    GetPage(name: Routes.cart, page: () => const CartView(), binding: CartBinding(), middlewares: _auth),
    GetPage(name: Routes.pabili, page: () => const PabiliView(), binding: PabiliBinding(), middlewares: _auth),
    GetPage(name: Routes.padala, page: () => const PadalaView(), binding: PadalaBinding(), middlewares: _auth),
    GetPage(name: Routes.checkout, page: () => const CheckoutView(), binding: CheckoutBinding(), middlewares: _auth),
    GetPage(name: Routes.tracking, page: () => const TrackingView(), binding: TrackingBinding(), middlewares: _auth),
    GetPage(name: Routes.profile, page: () => const ProfileView(), binding: ProfileBinding(), middlewares: _auth),
    GetPage(name: Routes.rate, page: () => const RatingView(), binding: RatingBinding(), middlewares: _auth),
  ];
}
