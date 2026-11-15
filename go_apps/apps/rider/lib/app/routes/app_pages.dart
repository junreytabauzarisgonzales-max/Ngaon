import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../../modules/active_job/binding.dart';
import '../../modules/active_job/view.dart';
import '../../modules/login/binding.dart';
import '../../modules/offer/binding.dart';
import '../../modules/offer/view.dart';
import '../../modules/pending/binding.dart';
import '../../modules/pending/view.dart';
import '../../modules/shell/binding.dart';
import '../../modules/shell/view.dart';
import '../../modules/signup/binding.dart';
import '../../modules/signup/view.dart';
import '../../modules/splash/binding.dart';
import '../../modules/splash/view.dart';
import 'app_routes.dart';

abstract class AppPages {
  static final _auth = [AuthMiddleware()];

  static final pages = <GetPage<dynamic>>[
    GetPage(name: Routes.splash, page: () => const SplashView(), binding: SplashBinding()),
    ...LoginRoutes.pages(RiderLoginBinding()),
    GetPage(name: Routes.signup, page: () => const SignupView(), binding: SignupBinding(), middlewares: _auth),
    GetPage(name: Routes.pending, page: () => const PendingView(), binding: PendingBinding(), middlewares: _auth),
    GetPage(name: Routes.home, page: () => const ShellView(), binding: ShellBinding(), middlewares: _auth),
    GetPage(name: Routes.offer, page: () => const OfferView(), binding: OfferBinding(), middlewares: _auth, fullscreenDialog: true),
    GetPage(name: Routes.activeJob, page: () => const ActiveJobView(), binding: ActiveJobBinding(), middlewares: _auth),
  ];
}
