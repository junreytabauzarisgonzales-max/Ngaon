import 'package:go_core/go_core.dart';

import 'app/bindings/initial_binding.dart';
import 'app/routes/app_pages.dart';
import 'app/routes/app_routes.dart';
import 'app/translations/customer_translations.dart';

Future<void> main() => bootstrapGoApp(
  config: AppConfig(app: GoApp.customer),
  title: 'Go Customer',
  initialRoute: Routes.splash,
  pages: AppPages.pages,
  translations: customerTranslations,
  initialBinding: InitialBinding(),
);
