import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';
import 'package:go_core/testing.dart';
import 'package:go_customer/app/bindings/initial_binding.dart';
import 'package:go_customer/app/routes/app_pages.dart';
import 'package:go_customer/app/routes/app_routes.dart';
import 'package:go_customer/app/translations/customer_translations.dart';
import 'package:go_customer/modules/ride/controller.dart';

Widget app(String initial) => buildGoApp(
  title: 'Ngain',
  initialRoute: initial,
  pages: AppPages.pages,
  translations: customerTranslations,
  initialBinding: InitialBinding(),
);

Finder status(String text) => find.byWidgetPredicate((w) => w is Text && w.key == const Key('tracking.status') && w.data == text);

void main() {
  testWidgets('shared login flow: phone -> OTP -> name -> home', (tester) async {
    usePhoneScreen(tester);
    final b = (await tester.runAsync(() => initGoTest(GoApp.customer)))!;
    await Get.find<StorageService>().setOnboardingDone();
    await tester.pumpWidget(app(Routes.splash));
    await pumpUntil(tester, find.byKey(const Key('login.phone')));

    await tester.enterText(find.byKey(const Key('login.phone')), '812');
    await tester.tap(find.byKey(const Key('login.phone.submit')));
    await tester.pump();
    expect(find.text('Enter a valid number like 9171234567'), findsOneWidget);

    // numbers ending 1111 are "new users" in mock mode -> name step
    await tester.enterText(find.byKey(const Key('login.phone')), '9171231111');
    await tester.tap(find.byKey(const Key('login.phone.submit')));
    await pumpUntil(tester, find.byKey(const Key('login.otp')));
    expect(find.textContaining('+63 917 ••• 1111'), findsOneWidget);
    expect(find.textContaining('Resend code in'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login.otp')), '000000');
    await pumpUntil(tester, find.text('Wrong code. Please try again.'));

    await tester.enterText(find.byKey(const Key('login.otp')), '123456');
    await pumpUntil(tester, find.byKey(const Key('login.name')));
    await tester.enterText(find.byKey(const Key('login.name')), 'Nur Hassan');
    await tester.tap(find.byKey(const Key('login.name.submit')));
    await pumpUntil(tester, find.byKey(const Key('home.greeting')));
    expect(tester.widget<Text>(find.byKey(const Key('home.greeting'))).data, contains('Nur'));
    expect(find.byKey(const Key('home.tile.ride')), findsOneWidget);
    expect(Get.find<AuthService>().isLoggedIn, isTrue);

    await tearDownGoTest(tester, b);
  });

  testWidgets('ride: quote -> book -> live tracking -> completed -> rate', (tester) async {
    usePhoneScreen(tester);
    final b = (await tester.runAsync(() => initGoTest(GoApp.customer, speed: 0.2)))!;
    await loginForTest(b, GoApp.customer); // fake zone: WS events must be pumped
    await tester.pumpWidget(app(Routes.home));
    await pumpUntil(tester, find.byKey(const Key('home.tile.ride')));

    await tester.tap(find.byKey(const Key('home.tile.ride')));
    await pumpUntil(tester, find.byKey(const Key('ride.see_price')));
    // Stops normally come from the shared map picker.
    final ride = Get.find<RideController>();
    ride.pickup.value = Stop(address: 'Lamion, Bongao', location: const LatLng(lat: 5.0251, lng: 119.7769));
    ride.dropoff.value = Stop(address: 'Provincial Capitol', location: const LatLng(lat: 5.0362, lng: 119.7795));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ride.see_price')));
    await pumpUntil(tester, find.textContaining('Book ·'));
    expect(find.text('Base fare'), findsOneWidget);

    await tester.tap(find.byKey(const Key('checkout.place')));
    await pumpUntil(tester, find.byKey(const Key('tracking.status')));
    expect(status('Finding a rider'), findsOneWidget);
    expect(find.byKey(const Key('tracking.cancel')), findsOneWidget, reason: 'cancel allowed while searching');

    await pumpUntil(tester, status('Rider on the way'));
    expect(find.text('Jamal H.'), findsOneWidget);
    expect(find.text('123 ABC'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
    expect(find.byKey(const Key('tracking.cancel')), findsOneWidget);

    await pumpUntil(tester, status('On the way to you'));
    expect(find.byKey(const Key('tracking.cancel')), findsNothing, reason: 'backend no longer allows cancel');

    await pumpUntil(tester, find.byKey(const Key('tracking.rate')));
    expect(find.text('Completed'), findsWidgets);
    await tester.tap(find.byKey(const Key('tracking.rate')));
    await pumpUntil(tester, find.text('Submit'));
    await tester.tap(find.text('Submit'));
    await pumpUntil(tester, find.text('Thanks for your feedback!'));

    await tearDownGoTest(tester, b);
  });

  testWidgets('circular nav tabs, profile from avatar, dark theme', (tester) async {
    usePhoneScreen(tester);
    final b = (await tester.runAsync(() => initGoTest(GoApp.customer)))!;
    await loginForTest(b, GoApp.customer);
    await tester.pumpWidget(app(Routes.home));
    await pumpUntil(tester, find.byKey(const Key('home.search')));
    for (final label in ['Home', 'Scan', 'Activity', 'Messages']) {
      expect(find.text(label), findsWidgets);
    }

    await tester.tap(find.byKey(const Key('nav.nav.messages')));
    await pumpUntil(tester, find.text('Earlier'));
    expect(find.text('Jamal H.'), findsWidgets, reason: 'past jobs with a rider are conversations');

    await tester.tap(find.byKey(const Key('nav.nav.activity')));
    await pumpUntil(tester, find.text('Past'));

    await tester.tap(find.byKey(const Key('nav.nav.home')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('home.profile')));
    await pumpUntil(tester, find.byKey(const Key('theme.selector')));
    await tester.tap(find.text('Dark'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(Get.find<ThemeService>().mode.value, ThemeMode.dark);
    expect(GoColors.isDark, isTrue);
    expect(Get.find<StorageService>().store.read<String>('theme_mode'), 'dark');

    await tester.tap(find.text('Light'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(GoColors.isDark, isFalse);
    await tearDownGoTest(tester, b);
  });
}
