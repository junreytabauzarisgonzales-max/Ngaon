import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:go_core/go_core.dart';

import '../routes/app_routes.dart';

/// Store, order board buckets, new-order alarm and wakelock.
class MerchantSessionService extends GetxService with WidgetsBindingObserver {
  final MerchantAdminRepository repo = Get.find();
  final GoWsClient ws = Get.find();
  final NotificationService notifications = Get.find();
  final PushService push = Get.find();
  final AuthService auth = Get.find();

  final account = Rxn<MerchantAccount>();
  final store = Rxn<Merchant>();
  final newOrders = <MerchantOrder>[].obs;
  final preparing = <MerchantOrder>[].obs;
  final ready = <MerchantOrder>[].obs;
  final done = <MerchantOrder>[].obs;
  final newCount = 0.obs;
  final loading = false.obs;
  final _subs = <StreamSubscription<dynamic>>[];
  bool _foreground = true;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _subs.add(ws.events.listen(_onEvent));
    _subs.add(ws.reconnected.listen((_) => loadOrders()));
    _subs.add(
      push.messages.stream.listen((m) {
        if (m.type.startsWith('order.')) loadOrders();
      }),
    );
    ever(newOrders, (_) => _syncAlarm());
    ever(store, (_) => _syncWakelock());
    auth.onLogout.add(() async {
      await notifications.stopAlarm();
      await notifications.keepAwake(false);
      account.value = null;
      store.value = null;
      for (final l in [newOrders, preparing, ready, done]) {
        l.clear();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) loadOrders();
    _syncWakelock();
  }

  Future<MerchantAccount> loadAccount() async {
    final a = await repo.me();
    account.value = a;
    store.value = a.merchant;
    return a;
  }

  /// Refetch board over REST (start, reconnect, push).
  Future<void> loadOrders() async {
    if (account.value == null) return;
    loading.value = true;
    try {
      final today = manilaDateString(DateTime.now());
      final r = await Future.wait([
        repo.orders(MerchantOrderFilter.newOrders),
        repo.orders(MerchantOrderFilter.preparing),
        repo.orders(MerchantOrderFilter.ready),
        repo.orders(MerchantOrderFilter.done, from: today, to: today),
      ]);
      newOrders.assignAll(r[0].items);
      preparing.assignAll(r[1].items);
      ready.assignAll(r[2].items);
      done.assignAll(r[3].items);
      for (final o in newOrders) {
        _notify(o);
      }
    } catch (e) {
      // Board keeps last known state; offline banner explains.
    } finally {
      loading.value = false;
    }
  }

  void _onEvent(WsEvent e) {
    switch (e) {
      case OrderNewEvent(:final order):
        upsert(order);
        _notify(order);
      case OrderUpdatedEvent(:final order):
        upsert(order);
      case MerchantUpdatedEvent(:final merchant):
        store.value = merchant;
      default:
        break;
    }
  }

  RxList<MerchantOrder> _bucketFor(MerchantOrderStatus s) => switch (s) {
    MerchantOrderStatus.newOrder => newOrders,
    MerchantOrderStatus.preparing => preparing,
    MerchantOrderStatus.ready => ready,
    _ => done,
  };

  /// Moves an order into the right column.
  void upsert(MerchantOrder o) {
    for (final l in [newOrders, preparing, ready, done]) {
      l.removeWhere((x) => x.id == o.id);
    }
    _bucketFor(o.status).insert(0, o);
    if (o.status != MerchantOrderStatus.newOrder) notifications.cancel(o.id.hashCode);
  }

  MerchantOrder? find(String id) => [...newOrders, ...preparing, ...ready, ...done].where((o) => o.id == id).firstOrNull;

  void _notify(MerchantOrder o) {
    if (_foreground) return;
    notifications.show(
      o.id.hashCode,
      'merchant.notif.title'.trParams({'code': o.code}),
      'merchant.notif.body'.trParams({'n': '${o.itemCount}', 'total': formatCentavos(o.subtotalCentavos)}),
      urgent: true,
      payload: '${WsTypes.orderNew}:${o.id}',
    );
  }

  /// Loud loop until every new order is accepted or rejected.
  void _syncAlarm() {
    newCount.value = newOrders.length;
    newOrders.isEmpty ? notifications.stopAlarm() : notifications.startAlarm();
  }

  void _syncWakelock() => notifications.keepAwake(store.value?.isOpen == true && _foreground);

  // ---- actions ----
  Future<bool> accept(MerchantOrder o, int prep) => _act(() => repo.accept(o.id, prep));
  Future<bool> reject(MerchantOrder o, RejectReason r, String? note) => _act(() => repo.reject(o.id, r, note: note));
  Future<bool> markReady(MerchantOrder o) => _act(() => repo.markReady(o.id));

  Future<bool> _act(Future<MerchantOrder> Function() fn) async {
    try {
      upsert(await fn());
      return true;
    } on ApiException catch (e) {
      GoErrors.show(e);
      if (e.code == ErrorCodes.orderAlreadyHandled) await loadOrders();
      return false;
    } catch (e) {
      GoErrors.show(e);
      return false;
    }
  }

  Future<void> setOpen(bool open) async {
    final m = await GoErrors.guard(() => repo.updateStore(StoreUpdate(isOpen: open)));
    if (m != null) store.value = m;
  }

  Future<void> pause(int minutes) async {
    final m = await GoErrors.guard(
      () => repo.updateStore(StoreUpdate(pausedUntil: DateTime.now().toUtc().add(Duration(minutes: minutes)))),
    );
    if (m != null) store.value = m;
  }

  Future<void> resume() async {
    final m = await GoErrors.guard(() => repo.updateStore(StoreUpdate(clearPause: true)));
    if (m != null) store.value = m;
  }

  void open(MerchantOrder o) => Get.toNamed(Routes.order, arguments: o.id);

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    super.onClose();
  }
}
