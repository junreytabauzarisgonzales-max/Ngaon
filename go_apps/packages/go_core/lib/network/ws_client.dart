import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ws_events.dart';

enum WsState { disconnected, connecting, connected }

/// Realtime channel used by all apps. Real and mock implementations.
abstract class GoWsClient {
  /// Typed server events.
  Stream<WsEvent> get events;

  /// Fires after a successful reconnect: apps refetch active state over REST.
  Stream<void> get reconnected;

  Rx<WsState> get state;

  bool get isConnected => state.value == WsState.connected;

  Future<void> connect();
  Future<void> disconnect();

  /// Sends `{ type, id, data }`. Returns false when not connected.
  bool send(String type, Map<String, dynamic> data);
}

/// Exponential backoff 1, 2, 4 … max 30 s, with up to 30% jitter.
class Backoff {
  Backoff({this.base = const Duration(seconds: 1), this.max = const Duration(seconds: 30), Random? random}) : _random = random ?? Random();
  final Duration base;
  final Duration max;
  final Random _random;
  int attempt = 0;

  /// Delay without jitter for the current attempt.
  Duration get rawDelay {
    final ms = base.inMilliseconds * pow(2, attempt).toInt();
    return Duration(milliseconds: min(ms, max.inMilliseconds));
  }

  Duration next() {
    final raw = rawDelay;
    attempt++;
    final jitter = (raw.inMilliseconds * 0.3 * _random.nextDouble()).round();
    return raw + Duration(milliseconds: jitter);
  }

  void reset() => attempt = 0;
}

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

/// Real WebSocket client with heartbeat, backoff reconnect and 4001 refresh.
class RealWsClient extends GoWsClient {
  RealWsClient({
    required this.wsUrl,
    required this.accessToken,
    required this.refreshToken,
    ChannelFactory? channelFactory,
    Backoff? backoff,
    this.pingInterval = const Duration(seconds: 25),
  }) : _factory = channelFactory ?? WebSocketChannel.connect,
       backoff = backoff ?? Backoff();

  /// Mutable for the dev server-address setting.
  String wsUrl;
  final String? Function() accessToken;
  final Future<bool> Function() refreshToken;
  final ChannelFactory _factory;
  final Backoff backoff;
  final Duration pingInterval;

  final _events = StreamController<WsEvent>.broadcast();
  final _reconnected = StreamController<void>.broadcast();
  @override
  final state = WsState.disconnected.obs;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _wanted = false;
  bool _hadConnection = false;

  /// Delays used for scheduled reconnects (exposed for tests).
  final List<Duration> scheduledDelays = [];

  @override
  Stream<WsEvent> get events => _events.stream;
  @override
  Stream<void> get reconnected => _reconnected.stream;

  @override
  Future<void> connect() async {
    _wanted = true;
    if (state.value != WsState.disconnected) return;
    await _open();
  }

  Future<void> _open() async {
    final token = accessToken();
    if (!_wanted || token == null) return;
    state.value = WsState.connecting;
    try {
      final channel = _factory(Uri.parse('$wsUrl/ws?token=${Uri.encodeQueryComponent(token)}'));
      _channel = channel;
      await channel.ready;
      state.value = WsState.connected;
      backoff.reset();
      if (_hadConnection) _reconnected.add(null);
      _hadConnection = true;
      _sub = channel.stream.listen(_onMessage, onDone: () => _onClosed(channel.closeCode), onError: (_) => _onClosed(null));
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(pingInterval, (_) => send(WsTypes.ping, const {}));
    } catch (e) {
      if (kDebugMode) debugPrint('WS connect failed: $e');
      _onClosed(null);
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      _events.add(WsEvent.parse(msg));
    } catch (_) {
      // ignore malformed frames
    }
  }

  Future<void> _onClosed(int? code) async {
    _pingTimer?.cancel();
    final sub = _sub;
    _sub = null;
    _channel = null;
    state.value = WsState.disconnected;
    // Don't await: cancelling a finished subscription may never complete.
    unawaited(sub?.cancel());
    if (!_wanted) return;
    if (code == 4001) {
      // token expired: refresh then reconnect immediately
      final ok = await refreshToken();
      if (ok) return _open();
    }
    final delay = backoff.next();
    scheduledDelays.add(delay);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _open);
  }

  @override
  Future<void> disconnect() async {
    _wanted = false;
    _hadConnection = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    final sub = _sub, channel = _channel;
    _sub = null;
    _channel = null;
    state.value = WsState.disconnected;
    backoff.reset();
    unawaited(sub?.cancel());
    await channel?.sink.close(1000);
  }

  @override
  bool send(String type, Map<String, dynamic> data) {
    final ch = _channel;
    if (ch == null || state.value != WsState.connected) return false;
    ch.sink.add(jsonEncode({'type': type, 'id': const Uuid().v4(), 'data': data}));
    return true;
  }
}
