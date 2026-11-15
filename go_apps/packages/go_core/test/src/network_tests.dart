import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';
import 'package:go_core/network/api_client.dart' as net;
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Fake server: tokens "old" are expired, "new" are valid.
class FakeAdapter implements HttpClientAdapter {
  int refreshCalls = 0;
  bool refreshFails = false;
  final requests = <String>[];

  ResponseBody _json(Object body, int status) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add('${o.method} ${o.path} ${o.headers['Authorization']}');
    if (o.path.endsWith('/auth/refresh')) {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (refreshFails) {
        return _json({
          'error': {'code': 'unauthorized', 'message': 'bad refresh'},
        }, 401);
      }
      return _json({
        'data': {'access_token': 'new', 'refresh_token': 'r2'},
        'meta': {},
      }, 200);
    }
    expect(o.headers['X-App'], 'customer');
    expect(o.headers['Accept-Language'], 'fil');
    if (o.headers['Authorization'] != 'Bearer new') {
      return _json({
        'error': {'code': 'token_expired', 'message': 'expired'},
      }, 401);
    }
    if (o.path.endsWith('/bad')) {
      return _json({
        'error': {
          'code': 'validation_failed',
          'message': 'nope',
          'fields': {'phone': 'invalid'},
        },
      }, 422);
    }
    return _json({
      'data': {'path': o.path},
      'meta': {'next_cursor': null},
    }, 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late FakeAdapter adapter;
  late SessionStore session;
  late ApiClient api;
  var expired = 0;

  setUp(() async {
    adapter = FakeAdapter();
    session = SessionStore(MemorySecureKeyValue());
    await session.save('old', 'r1');
    expired = 0;
    api = ApiClient(
      config: AppConfig(app: GoApp.customer, apiBaseUrl: 'http://test', useMockApi: false, enablePlatformPlugins: false),
      session: session,
      languageCode: () => 'fil',
      onSessionExpired: () async => expired++,
      adapter: adapter,
    );
  });

  test('concurrent 401 token_expired triggers exactly one refresh, all retried', () async {
    final results = await Future.wait(List.generate(5, (i) => api.get('/things/$i', net.asMap)));
    expect(results.map((r) => r['path']), ['/things/0', '/things/1', '/things/2', '/things/3', '/things/4']);
    expect(adapter.refreshCalls, 1);
    expect(session.accessToken, 'new');
    expect(session.refreshToken, 'r2');
    expect(expired, 0);
  });

  test('failed refresh clears the session and logs out', () async {
    adapter.refreshFails = true;
    await expectLater(api.get('/x', net.asMap), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'token_expired')));
    expect(adapter.refreshCalls, 1);
    expect(session.hasSession, isFalse);
    expect(expired, 1);
  });

  test('error envelope becomes typed ApiException', () async {
    await session.save('new', 'r1');
    await expectLater(
      api.send('POST', '/bad', (d) => d),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'validation_failed')
            .having((e) => e.fields['phone'], 'field', 'invalid')
            .having((e) => e.httpStatus, 'status', 422),
      ),
    );
  });

  test('Idempotency-Key is sent', () async {
    await session.save('new', 'r1');
    String? seen;
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          seen = o.headers['Idempotency-Key'] as String?;
          h.next(o);
        },
      ),
    );
    await api.send('POST', '/jobs', (d) => d, idempotencyKey: 'k-1');
    expect(seen, 'k-1');
  });

  group('WebSocket', () {
    test('backoff doubles to 30 s with bounded jitter', () {
      final b = Backoff(random: Random(1));
      final raws = <int>[];
      for (var i = 0; i < 8; i++) {
        raws.add(b.rawDelay.inSeconds);
        final d = b.next();
        expect(d.inMilliseconds, inInclusiveRange(raws.last * 1000, (raws.last * 1300).round()));
      }
      expect(raws, [1, 2, 4, 8, 16, 30, 30, 30]);
      b.reset();
      expect(b.rawDelay.inSeconds, 1);
    });

    test('reconnects with backoff, emits reconnected, refreshes on 4001', () {
      fakeAsync((async) {
        final channels = <FakeChannel>[];
        var failNext = 0;
        var refreshed = 0;
        final client = RealWsClient(
          wsUrl: 'ws://test',
          accessToken: () => 'tok',
          refreshToken: () async {
            refreshed++;
            return true;
          },
          backoff: Backoff(random: Random(2)),
          channelFactory: (uri) {
            expect(uri.toString(), 'ws://test/ws?token=tok');
            if (failNext > 0) {
              failNext--;
              throw const SocketLikeException();
            }
            final c = FakeChannel();
            channels.add(c);
            return c;
          },
        );
        var reconnects = 0;
        client.reconnected.listen((_) => reconnects++);
        final events = <WsEvent>[];
        client.events.listen(events.add);

        client.connect();
        async.flushMicrotasks();
        expect(client.state.value, WsState.connected);

        // server pushes an event
        channels.last.incoming.add(
          jsonEncode({
            'type': 'offer.expired',
            'id': 'e1',
            'data': {'offer_id': 'o1'},
          }),
        );
        async.flushMicrotasks();
        expect(events.single, isA<OfferExpiredEvent>().having((e) => e.offerId, 'id', 'o1'));

        // heartbeat
        async.elapse(const Duration(seconds: 25));
        expect(channels.last.sent.map((s) => jsonDecode(s as String)['type']), contains('ping'));

        // drop + two failed attempts: delays 1 s, 2 s, 4 s (+ jitter)
        failNext = 2;
        channels.last.serverClose(1006);
        async.flushMicrotasks();
        expect(client.state.value, WsState.disconnected);
        async.elapse(const Duration(seconds: 10));
        expect(client.scheduledDelays.map((d) => d.inSeconds), [1, 2, 4]);
        expect(client.state.value, WsState.connected);
        expect(reconnects, 1);

        // 4001 => refresh then immediate reconnect, no backoff
        channels.last.serverClose(4001);
        async.flushMicrotasks();
        expect(refreshed, 1);
        expect(client.state.value, WsState.connected);
        expect(client.scheduledDelays, hasLength(3));
        expect(reconnects, 2);

        client.disconnect();
        async.flushMicrotasks();
        expect(client.state.value, WsState.disconnected);
      });
    });
  });
}

class SocketLikeException implements Exception {
  const SocketLikeException();
}

class FakeChannel with StreamChannelMixin<dynamic> implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final sent = <Object?>[];
  int? _code;
  late final _FakeSink _sink = _FakeSink(this);

  void serverClose(int code) {
    _code = code;
    incoming.close();
  }

  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => _sink;
  @override
  Future<void> get ready => Future.value();
  @override
  String? get protocol => null;
  @override
  int? get closeCode => _code;
  @override
  String? get closeReason => null;
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this.channel);
  final FakeChannel channel;
  @override
  void add(Object? data) => channel.sent.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<Object?> stream) => stream.forEach(add);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
  @override
  Future<void> get done => Future.value();
}
