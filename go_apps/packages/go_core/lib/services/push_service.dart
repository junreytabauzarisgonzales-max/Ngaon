import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';

import '../config/app_config.dart';
import '../repositories/repositories.dart';
import 'notification_service.dart';

/// Push payloads only carry `type` + IDs (`job_id`, `offer_id`, `order_id`).
class PushMessage {
  PushMessage(this.type, this.data);
  final String type;
  final Map<String, dynamic> data;
  String? get jobId => data['job_id'] as String?;
  String? get offerId => data['offer_id'] as String?;
  String? get orderId => data['order_id'] as String?;
}

/// Shows a high-priority local notification for urgent pushes when the app
/// is in the background/killed (Android data-only message).
@pragma('vm:entry-point')
Future<void> goFirebaseBackgroundHandler(RemoteMessage message) async {
  final type = message.data['type'] as String?;
  if (type != 'offer.new' && type != 'order.new') return;
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  final ch = NotificationService.alarmChannel;
  await plugin.show(
    id: type.hashCode,
    title: type == 'offer.new' ? 'New job offer' : 'New order',
    body: type == 'offer.new' ? 'Open Ngain Rider to accept' : 'Open Ngain Merchant to accept',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        ch.id,
        ch.name,
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
      ),
    ),
    payload: '$type:${message.data['offer_id'] ?? message.data['order_id'] ?? ''}',
  );
}

class PushService extends GetxService {
  bool _available = false;
  final messages = StreamController<PushMessage>.broadcast();

  bool get available => _available;

  Future<PushService> init() async {
    if (!AppConfig.current.enablePlatformPlugins) return this;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(goFirebaseBackgroundHandler);
      await FirebaseMessaging.instance.requestPermission();
      FirebaseMessaging.onMessage.listen((m) => messages.add(PushMessage('${m.data['type']}', m.data)));
      FirebaseMessaging.onMessageOpenedApp.listen((m) => messages.add(PushMessage('${m.data['type']}', m.data)));
      _available = true;
    } catch (e) {
      // No google-services.json configured: push disabled, app still works.
      if (kDebugMode) debugPrint('Push disabled: $e');
    }
    return this;
  }

  /// Registers the FCM token with `POST /me/devices` (after login).
  Future<void> register() async {
    if (!_available) return;
    try {
      // Contract uses classic FCM registration tokens (`fcm_token`); see
      // API_CONTRACT.md note on FCM 17's FID-based direct send.
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await Get.find<AuthRepository>().registerDevice(token, AppConfig.current.app);
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh.listen((t) => Get.find<AuthRepository>().registerDevice(t, AppConfig.current.app));
    } catch (e) {
      if (kDebugMode) debugPrint('FCM token registration failed: $e');
    }
  }
}
