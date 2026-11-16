import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_core/go_core.dart';

/// Returns 429 (Retry-After: 1) for the first [limited] calls, then 200.
class RateLimitedAdapter implements HttpClientAdapter {
  RateLimitedAdapter(this.limited);
  int limited;
  int calls = 0;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    paths.add('${o.method} ${o.uri}');
    if (limited > 0) {
      limited--;
      return ResponseBody.fromString(
        jsonEncode({'error': {'code': 'rate_limited', 'message': 'slow down'}}),
        429,
        headers: {Headers.contentTypeHeader: ['application/json'], 'retry-after': ['1']},
      );
    }
    return ResponseBody.fromString(jsonEncode({'data': {'ok': true}, 'meta': {}}), 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

ApiClient client(RateLimitedAdapter a) {
  final session = SessionStore(MemorySecureKeyValue());
  return ApiClient(
    config: AppConfig(app: GoApp.customer, apiBaseUrl: 'http://one:8080', useMockApi: false, enablePlatformPlugins: false),
    session: session,
    languageCode: () => 'en',
    onSessionExpired: () async {},
    adapter: a,
  );
}

void main() {
  test('GET waits for Retry-After once, then succeeds', () async {
    final a = RateLimitedAdapter(1);
    final sw = Stopwatch()..start();
    final r = await client(a).request('GET', '/jobs');
    expect((r.data! as Map)['ok'], isTrue);
    expect(a.calls, 2);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(900));
  });

  test('POST without Idempotency-Key is not retried; error carries Retry-After', () async {
    final a = RateLimitedAdapter(1);
    await expectLater(
      client(a).request('POST', '/auth/otp/request', body: {}),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'rate_limited').having((e) => e.retryAfterSeconds, 'wait', 1)),
    );
    expect(a.calls, 1);
  });

  test('POST with Idempotency-Key is retried after Retry-After', () async {
    final a = RateLimitedAdapter(1);
    await client(a).request('POST', '/jobs', body: {}, idempotencyKey: 'k');
    expect(a.calls, 2);
  });

  test('setServer repoints requests at runtime', () async {
    final a = RateLimitedAdapter(0);
    final c = client(a);
    await c.request('GET', '/me');
    c.setServer('http://two:9090');
    await c.request('GET', '/me');
    expect(a.paths, ['GET http://one:8080/api/v1/me', 'GET http://two:9090/api/v1/me']);
    expect(AppConfig.wsFor('https://api.ngaon.example'), 'wss://api.ngaon.example');
  });
}
