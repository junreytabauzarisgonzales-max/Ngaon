import 'package:go_core/go_core.dart';

import 'app/bindings/initial_binding.dart';
import 'app/routes/app_pages.dart';
import 'app/routes/app_routes.dart';
import 'app/translations/merchant_translations.dart';

Future<void> main() => bootstrapGoApp(
  config: AppConfig(app: GoApp.merchant),
  title: 'Go Merchant',
  initialRoute: Routes.splash,
  pages: AppPages.pages,
  translations: merchantTranslations,
  initialBinding: InitialBinding(),
);
