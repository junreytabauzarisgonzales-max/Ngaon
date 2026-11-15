import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';
import 'package:go_core/testing.dart';
import 'package:go_rider/app/bindings/initial_binding.dart';
import 'package:go_rider/app/routes/app_pages.dart';
import 'package:go_rider/app/routes/app_routes.dart';
import 'package:go_rider/app/services/rider_session_service.dart';
import 'package:go_rider/app/translations/rider_translations.dart';

Widget app() => buildGoApp(
  title: 'Go Rider',
  initialRoute: Routes.splash,
  pages: AppPages.pages,
  translations: riderTranslations,
  initialBinding: InitialBinding(),
);

Finder jobStatus(String text) => find.byWidgetPredicate((w) => w is Text && w.key == const Key('job.status') && w.data == text);

Future<void> goOffline(WidgetTester tester) async {
  final s = Get.find<RiderSessionService>();
  // Don't await: mock latency only advances while the test pumps.
  if (s.online) s.setOnline(false);
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('online -> offer -> accept -> active job steps -> complete', (tester) async {
    usePhoneScreen(tester);
    final b = (await tester.runAsync(() => initGoTest(GoApp.rider, speed: 0.2)))!;
    await loginForTest(b, GoApp.rider, phone: '+639181112222');
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.text('You are offline'));

    await tester.tap(find.byKey(const Key('rider.toggle')));
    await pumpUntil(tester, find.text('You are online'));

    // offer.new arrives -> full-screen offer with countdown
    await pumpUntil(tester, find.byKey(const Key('offer.accept')));
    expect(find.byKey(const Key('offer.earnings')), findsOneWidget);
    expect(Get.find<NotificationService>().alarmActive.value, isTrue, reason: 'looping alarm while offer is shown');
    await tester.tap(find.byKey(const Key('offer.accept')));
    await pumpUntil(tester, jobStatus('Rider on the way'));
    expect(Get.find<NotificationService>().alarmActive.value, isFalse);
    expect(find.byKey(const Key('job.collect')), findsOneWidget, reason: 'first mock offer is a cash ride');

    for (final step in ['Arrived at pickup', 'Picked up', 'Arrived', 'Complete']) {
      await pumpUntil(tester, find.descendant(of: find.byKey(const Key('job.primary')), matching: find.text(step)));
      await tester.tap(find.byKey(const Key('job.primary')));
      await tester.pump();
    }
    await pumpUntil(tester, find.byKey(const Key('job.done')));
    expect(Get.find<RiderSessionService>().activeJob.value, isNull);

    await goOffline(tester);
    await tearDownGoTest(tester, b);
  });

  testWidgets('cannot go online with low balance: explains and offers top up', (tester) async {
    usePhoneScreen(tester);
    final b = (await tester.runAsync(() => initGoTest(GoApp.rider)))!;
    b.riderProfile['balance_centavos'] = 5000;
    await loginForTest(b, GoApp.rider, phone: '+639181112222');
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.text('You are offline'));

    await tester.tap(find.byKey(const Key('rider.toggle')));
    await pumpUntil(tester, find.text('Wallet balance too low'));
    expect(find.text('You are offline'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Top up'), findsOneWidget);

    await tearDownGoTest(tester, b);
  });

  testWidgets('new rider (incomplete profile) is routed to signup', (tester) async {
    usePhoneScreen(tester);
    final b = (await tester.runAsync(() => initGoTest(GoApp.rider)))!;
    await loginForTest(b, GoApp.rider, phone: '+639181111111');
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.text('Become a Go rider'));
    expect(find.text("Driver's license"), findsOneWidget);
    expect(find.text('Submit (0/4 documents)'), findsOneWidget);
    await tearDownGoTest(tester, b);
  });
}
