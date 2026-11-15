import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/app_config.dart';

/// Local notifications, looping alarm sound + vibration, wakelock.
class NotificationService extends GetxService {
  final _plugin = FlutterLocalNotificationsPlugin();
  AudioPlayer? _playerInstance;
  AudioPlayer get _player => _playerInstance ??= AudioPlayer();
  Timer? _vibrateTimer;
  final alarmActive = false.obs;

  /// Tapped notification payloads (`type:id`), for deep links.
  final taps = StreamController<String>.broadcast();

  bool get _real => AppConfig.current.enablePlatformPlugins;

  static const alarmChannel = AndroidNotificationChannel(
    'go_alarm',
    'Orders and offers',
    description: 'New orders and job offers',
    importance: Importance.max,
    playSound: true,
  );
  static const generalChannel = AndroidNotificationChannel('go_general', 'Updates', importance: Importance.high);

  Future<NotificationService> init() async {
    if (!_real) return this;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) taps.add(r.payload!);
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(alarmChannel);
    await android?.createNotificationChannel(generalChannel);
    await android?.requestNotificationsPermission();
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.gainTransient,
        ),
      ),
    );
    return this;
  }

  Future<void> show(int id, String title, String body, {bool urgent = false, String? payload}) async {
    if (!_real) return;
    final ch = urgent ? alarmChannel : generalChannel;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          ch.id,
          ch.name,
          importance: ch.importance,
          priority: urgent ? Priority.max : Priority.high,
          category: urgent ? AndroidNotificationCategory.alarm : null,
          fullScreenIntent: urgent,
          ongoing: urgent,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> cancel(int id) async {
    if (_real) await _plugin.cancel(id: id);
  }

  /// Loud looping sound + vibration until [stopAlarm].
  Future<void> startAlarm() async {
    if (alarmActive.value) return;
    alarmActive.value = true;
    if (!_real) return;
    try {
      await _player.play(AssetSource('packages/go_core/assets/sounds/alarm.wav'), volume: 1);
    } catch (_) {}
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) => HapticFeedback.vibrate());
  }

  Future<void> stopAlarm() async {
    if (!alarmActive.value) return;
    alarmActive.value = false;
    _vibrateTimer?.cancel();
    if (_real) await _player.stop();
  }

  Future<void> keepAwake(bool on) async {
    if (!_real) return;
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {}
  }

  @override
  void onClose() {
    _playerInstance?.dispose();
    super.onClose();
  }
}
