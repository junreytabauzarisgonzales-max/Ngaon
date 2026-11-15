import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../routes/app_routes.dart';

/// Why the rider cannot go online right now.
enum OnlineBlocker { notApproved, noLocation, lowBalance }

/// Rider state shared by all screens: profile, online status, location
/// streaming, offers (with alarm) and the active job.
class RiderSessionService extends GetxService with WidgetsBindingObserver {
  final RiderRepository repo = Get.find();
  final GoWsClient ws = Get.find();
  final LocationService location = Get.find();
  final NotificationService notifications = Get.find();
  final PushService push = Get.find();
  final AuthService auth = Get.find();

  final profile = Rxn<RiderProfile>();
  final activeJob = Rxn<Job>();
  final offer = Rxn<JobOffer>();
  final toggling = false.obs;
  final lastPingAt = Rxn<DateTime>();

  bool get online => profile.value?.isOnline ?? false;

  Timer? _ticker;
  DateTime? _lastSent;
  LatLng? _lastSentAt;
  bool _foreground = true;
  final _subs = <StreamSubscription<dynamic>>[];

  static const offerNotificationId = 4001;
  static const movingInterval = Duration(seconds: 5);
  static const stationaryInterval = Duration(seconds: 20);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _subs.add(ws.events.listen(_onEvent));
    _subs.add(ws.reconnected.listen((_) => refreshAll()));
    _subs.add(
      push.messages.stream.listen((m) {
        if (m.type == WsTypes.offerNew || m.type == WsTypes.jobUpdated) refreshAll();
      }),
    );
    _subs.add(
      notifications.taps.stream.listen((p) {
        if (p.startsWith(WsTypes.offerNew)) refreshAll();
      }),
    );
    auth.onLogout.add(_onLogout);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _foreground = state == AppLifecycleState.resumed;

  // ---------- loading ----------
  Future<RiderProfile> loadProfile() async {
    final p = await repo.me();
    profile.value = p;
    if (p.isOnline) _startTracking();
    return p;
  }

  /// Refetch active state over REST (after reconnect / push / app start).
  Future<void> refreshAll() async {
    try {
      await loadProfile();
      activeJob.value = await repo.activeJob();
      final o = await repo.currentOffer();
      if (o != null && offer.value?.id != o.id) _showOffer(o);
    } catch (_) {}
  }

  // ---------- online / offline ----------
  Future<List<OnlineBlocker>> blockers() async {
    final p = profile.value;
    return [
      if (p?.status != RiderStatus.approved) OnlineBlocker.notApproved,
      if (await location.request() != LocationPermissionState.granted) OnlineBlocker.noLocation,
      if (p != null && !p.hasEnoughBalance) OnlineBlocker.lowBalance,
    ];
  }

  /// Returns blockers (empty on success).
  Future<List<OnlineBlocker>> setOnline(bool value) async {
    if (toggling.value) return const [];
    toggling.value = true;
    try {
      if (value) {
        final b = await blockers();
        if (b.isNotEmpty) return b;
      }
      final here = await location.current();
      profile.value = await repo.setStatus(online: value, location: here);
      value ? _startTracking() : await _stopTracking();
      return const [];
    } catch (e) {
      if (e is ApiException && e.code == ErrorCodes.insufficientBalance) return const [OnlineBlocker.lowBalance];
      if (e is ApiException && e.code == ErrorCodes.riderNotApproved) return const [OnlineBlocker.notApproved];
      GoErrors.show(e);
      return const [];
    } finally {
      toggling.value = false;
    }
  }

  void _startTracking() {
    if (_ticker != null) return;
    location.startTracking(foregroundTitle: 'rider.fg_title'.tr, foregroundText: 'rider.fg_text'.tr);
    _ticker = Timer.periodic(movingInterval, (_) => _tick());
    _tick();
  }

  Future<void> _stopTracking() async {
    _ticker?.cancel();
    _ticker = null;
    await location.stopTracking();
  }

  /// Sends `rider.location` every 5 s while moving, 20 s when stationary;
  /// falls back to `POST /rider/location` when the socket is down.
  Future<void> _tick() async {
    final pos = location.last.value;
    final here = pos?.location ?? await location.current();
    final now = DateTime.now();
    final moved = _lastSentAt == null || here.distanceTo(_lastSentAt!) > 15;
    final moving = (pos?.speedKph ?? 0) > 3 || moved;
    if (_lastSent != null && !moving && now.difference(_lastSent!) < stationaryInterval) return;
    final ping = LocationPing(location: here, heading: pos?.heading, speedKph: pos?.speedKph, recordedAt: now.toUtc());
    _lastSent = now;
    _lastSentAt = here;
    lastPingAt.value = now;
    if (!ws.send(WsTypes.riderLocation, ping.toJson())) {
      try {
        await repo.postLocation(ping);
      } catch (_) {}
    }
  }

  // ---------- realtime ----------
  void _onEvent(WsEvent e) {
    switch (e) {
      case OfferNewEvent(:final offer):
        _showOffer(offer);
      case OfferExpiredEvent(:final offerId):
        if (offer.value?.id == offerId) clearOffer(expired: true);
      case JobUpdatedEvent(:final job):
        if (activeJob.value?.id == job.id || (activeJob.value == null && !job.status.isFinal && job.rider != null)) {
          activeJob.value = job.status.isFinal && job.status == JobStatus.cancelled ? null : job;
        }
      case RiderProfileUpdatedEvent(:final profile):
        this.profile.value = profile;
      default:
        break;
    }
  }

  void _showOffer(JobOffer o) {
    if (activeJob.value != null && !activeJob.value!.status.isFinal) return;
    offer.value = o;
    notifications.startAlarm();
    if (!_foreground) {
      notifications.show(
        offerNotificationId,
        'rider.offer.notif_title'.tr,
        'rider.offer.notif_body'.trParams({'amount': formatCentavos(o.earningsCentavos)}),
        urgent: true,
        payload: '${WsTypes.offerNew}:${o.id}',
      );
    }
    if (Get.currentRoute != Routes.offer) Get.toNamed(Routes.offer);
  }

  void clearOffer({bool expired = false}) {
    offer.value = null;
    notifications.stopAlarm();
    notifications.cancel(offerNotificationId);
    if (Get.currentRoute == Routes.offer) Get.back();
    if (expired) GoErrors.toast('error.offer_expired'.tr);
  }

  Future<void> accept() async {
    final o = offer.value;
    if (o == null) return;
    notifications.stopAlarm();
    try {
      activeJob.value = await repo.acceptOffer(o.id);
      offer.value = null;
      await notifications.cancel(offerNotificationId);
      Get.offNamed(Routes.activeJob);
    } catch (e) {
      GoErrors.show(e);
      clearOffer();
    }
  }

  Future<void> decline({String? reason}) async {
    final o = offer.value;
    clearOffer();
    if (o == null) return;
    try {
      await repo.declineOffer(o.id, reason: reason);
    } catch (_) {}
  }

  Future<void> _onLogout() async {
    await _stopTracking();
    await notifications.stopAlarm();
    profile.value = null;
    activeJob.value = null;
    offer.value = null;
  }

  /// Route for the rider's current account state.
  static String routeFor(RiderProfile p) => switch (p.status) {
    RiderStatus.incomplete => Routes.signup,
    RiderStatus.approved => Routes.home,
    _ => Routes.pending,
  };

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    _ticker?.cancel();
    super.onClose();
  }
}
