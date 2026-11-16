import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';
import 'package:go_core/testing.dart';
import 'package:go_merchant/app/bindings/initial_binding.dart';
import 'package:go_merchant/app/routes/app_pages.dart';
import 'package:go_merchant/app/routes/app_routes.dart';
import 'package:go_merchant/app/translations/merchant_translations.dart';

Widget app() => buildGoApp(
  title: 'Ngain Merchant',
  initialRoute: Routes.splash,
  pages: AppPages.pages,
  translations: merchantTranslations,
  initialBinding: InitialBinding(),
);

/// Store closed => the simulator sends no extra orders; the seeded NG-4831 is "new".
Future<MockBackend> start(WidgetTester tester, {String phone = '+639193334444'}) async {
  final b = (await tester.runAsync(() => initGoTest(GoApp.merchant, speed: 0.2)))!;
  b.merchantAccount['merchant']['is_open'] = false;
  await loginForTest(b, GoApp.merchant, phone: phone);
  await tester.pumpWidget(app());
  return b;
}

void main() {
  testWidgets('new order alarm -> accept with prep time -> rider handoff -> mark ready', (tester) async {
    usePhoneScreen(tester);
    final b = await start(tester);
    await pumpUntil(tester, find.byKey(const Key('order.NG-4831')));
    final alarm = Get.find<NotificationService>().alarmActive;
    expect(alarm.value, isTrue, reason: 'looping alarm while an order is new');

    await tester.tap(find.byKey(const Key('order.NG-4831')));
    await pumpUntil(tester, find.byKey(const Key('order.accept')));
    expect(find.textContaining('Auto-reject in'), findsOneWidget);
    expect(find.text('Rider pays you at pickup'), findsOneWidget, reason: 'seeded order is cash');
    expect(find.text('“Please add extra sauce”'), findsNothing);
    expect(find.text('Notes: Please add extra sauce'), findsOneWidget);

    await tester.tap(find.byKey(const Key('order.accept')));
    await pumpUntil(tester, find.byKey(const Key('prep.confirm')));
    await tester.pump(const Duration(milliseconds: 600)); // sheet slide-in
    await tester.tap(find.widgetWithText(ChoiceChip, '20'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('prep.confirm')));
    await pumpUntil(tester, find.byKey(const Key('order.ready')));
    expect(find.text('Prep time: 20 min'), findsOneWidget);
    expect(alarm.value, isFalse, reason: 'alarm stops when no new orders remain');

    await pumpUntil(tester, find.byKey(const Key('order.rider')));
    expect(find.text('Jamal H.'), findsOneWidget);
    expect(find.text('Plate 123 ABC'), findsOneWidget);

    await tester.tap(find.byKey(const Key('order.ready')));
    await pumpUntil(tester, find.text('Ready'));
    expect(find.byKey(const Key('order.ready')), findsNothing);

    await tearDownGoTest(tester, b);
  });

  testWidgets('tablet board shows columns; reject with a reason', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final b = await start(tester);
    await pumpUntil(tester, find.byKey(const Key('order.NG-4831')));
    for (final h in ['New (1)', 'Preparing (0)', 'Ready (0)']) {
      expect(find.text(h), findsOneWidget);
    }
    expect(find.byType(TabBar), findsNothing, reason: 'columns, not tabs, on wide screens');

    await tester.tap(find.byKey(const Key('order.NG-4831')));
    await pumpUntil(tester, find.byKey(const Key('order.reject')));
    await tester.tap(find.byKey(const Key('order.reject')));
    await pumpUntil(tester, find.text('Too busy'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Too busy'));
    await tester.tap(find.byKey(const Key('reject.confirm')));
    await pumpUntil(tester, find.text('New (0)'));
    expect(b.orders.firstWhere((o) => o['code'] == 'NG-4831')['reject_reason'], 'too_busy');
    expect(Get.find<NotificationService>().alarmActive.value, isFalse);

    await tearDownGoTest(tester, b);
  });

  testWidgets('number ending 0000 is not a merchant', (tester) async {
    usePhoneScreen(tester);
    final b = await start(tester, phone: '+639170000000');
    await pumpUntil(tester, find.byKey(const Key('not_merchant')));
    expect(find.text('This number is not registered as a merchant. Contact Ngain support.'), findsOneWidget);
    await tearDownGoTest(tester, b);
  });
}
