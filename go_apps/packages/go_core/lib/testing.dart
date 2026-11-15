/// Helpers for widget tests in the apps (not exported by go_core.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'go_core.dart';

/// Boots go_core in mock mode with in-memory storage and no platform plugins.
/// Call inside `tester.runAsync` (fixtures load from the asset bundle).
Future<MockBackend> initGoTest(GoApp app, {double speed = 0.01, bool simulate = true}) async {
  Get.testMode = true;
  Get.reset();
  final b = MockBackend(app: app, speed: speed, simulate: simulate);
  await b.init();
  await initGoCore(
    AppConfig(app: app, useMockApi: true, enablePlatformPlugins: false, mockSpeed: speed, apiBaseUrl: 'http://test', wsUrl: 'ws://test'),
    store: MemoryStore(),
    secure: MemorySecureKeyValue(),
    mockBackend: b,
  );
  return b;
}

/// Logs in through the backend directly (skips the OTP screens). Call it
/// outside `runAsync` so the WebSocket subscription lives in the fake zone.
Future<void> loginForTest(MockBackend b, GoApp app, {String phone = '+639171234567'}) async {
  final r = AuthResult.fromJson(b.verifyOtp(phone, MockBackend.mockOtp, app));
  await Get.find<AuthService>().completeLogin(r);
}

/// Pumps frames until [finder] matches or [maxSteps] * [step] elapses.
Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration step = const Duration(milliseconds: 100), int maxSteps = 300}) async {
  for (var i = 0; i < maxSteps; i++) {
    await tester.pump(step);
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

/// Tears down simulations and the widget tree so no timers stay pending.
Future<void> tearDownGoTest(WidgetTester tester, MockBackend b) async {
  b.stopSimulations();
  // Let snackbars / route animations finish before unmounting.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 5));
  Get.reset();
}

/// Use a typical phone screen (360 x 800 dp) instead of the 800 x 600 test default.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}
