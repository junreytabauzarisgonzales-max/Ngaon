import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/misc.dart';
import 'api_exception.dart';
import 'session_store.dart';

typedef JsonMap = Map<String, dynamic>;

/// Envelope `{ data, meta }`.
class ApiResponse {
  ApiResponse(this.data, this.meta);
  final Object? data;
  final JsonMap meta;
  String? get nextCursor => meta['next_cursor'] as String?;
}

/// Thin Dio wrapper: base URL, 15 s timeouts, headers, token refresh, retry,
/// debug logging, envelope unwrapping and error mapping.
class ApiClient {
  ApiClient({
    required this.config,
    required this.session,
    required this.languageCode,
    required this.onSessionExpired,
    this.onNetworkStatus,
    HttpClientAdapter? adapter,
  }) {
    final options = BaseOptions(
      baseUrl: config.apiRoot,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
    );
    dio = Dio(options);
    _refreshDio = Dio(options);
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
      _refreshDio.httpClientAdapter = adapter;
    }
    final headers = HeadersInterceptor(config: config, languageCode: languageCode);
    _refreshDio.interceptors.add(headers);
    dio.interceptors.addAll([
      headers,
      AuthInterceptor(session: session, dio: dio, refresh: refreshTokens),
      RetryInterceptor(dio: dio),
      if (kDebugMode) RedactingLogInterceptor(),
    ]);
  }

  final AppConfig config;
  final SessionStore session;
  final String Function() languageCode;

  /// Called when refresh fails: the app logs out.
  final Future<void> Function() onSessionExpired;

  /// Reports reachability (true = a request reached the server).
  final void Function(bool online)? onNetworkStatus;

  late final Dio dio;
  late final Dio _refreshDio;
  Future<bool>? _refreshing;

  static String newIdempotencyKey() => const Uuid().v4();

  /// Points both clients at another server (dev server-address setting).
  void setServer(String apiBase) {
    dio.options.baseUrl = '$apiBase/api/v1';
    _refreshDio.options.baseUrl = '$apiBase/api/v1';
  }

  /// Refreshes tokens once; concurrent callers share the same future.
  Future<bool> refreshTokens() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final rt = session.refreshToken;
    if (rt == null) return false;
    try {
      final res = await _refreshDio.post('/auth/refresh', data: {'refresh_token': rt});
      final data = (res.data as Map)['data'] as Map;
      await session.save(data['access_token'] as String, data['refresh_token'] as String);
      return true;
    } on DioException catch (e) {
      final ex = ApiException.fromDio(e);
      if (ex.isNetwork) return false; // keep session, try again later
      await session.clear();
      await onSessionExpired();
      return false;
    }
  }

  Future<ApiResponse> request(String method, String path, {Object? body, Map<String, dynamic>? query, String? idempotencyKey}) async {
    try {
      final res = await dio.request<Object?>(
        path,
        data: body,
        queryParameters: query == null ? null : (Map.of(query)..removeWhere((k, v) => v == null)),
        options: Options(method: method, headers: {'Idempotency-Key': ?idempotencyKey}),
      );
      onNetworkStatus?.call(true);
      final map = res.data is Map ? res.data as Map : const {};
      return ApiResponse(map['data'], Map<String, dynamic>.from((map['meta'] as Map?) ?? const {}));
    } on DioException catch (e) {
      final ex = ApiException.fromDio(e);
      onNetworkStatus?.call(!ex.isNetwork);
      throw ex;
    }
  }

  Future<T> get<T>(String path, T Function(Object? data) parse, {Map<String, dynamic>? query}) async =>
      parse((await request('GET', path, query: query)).data);

  Future<Page<T>> getPage<T>(String path, T Function(JsonMap) parse, {Map<String, dynamic>? query}) async {
    final res = await request('GET', path, query: query);
    final list = (res.data as List? ?? const []).cast<Map>();
    return Page(list.map((m) => parse(Map<String, dynamic>.from(m))).toList(), res.nextCursor);
  }

  Future<T> send<T>(String method, String path, T Function(Object? data) parse, {Object? body, String? idempotencyKey}) async =>
      parse((await request(method, path, body: body ?? const {}, idempotencyKey: idempotencyKey)).data);

  /// For endpoints returning `{}`.
  Future<void> sendVoid(String method, String path, {Object? body}) => request(method, path, body: body ?? const {});
}

JsonMap asMap(Object? data) => Map<String, dynamic>.from(data as Map);
List<T> asList<T>(Object? data, T Function(JsonMap) parse) =>
    (data as List? ?? const []).map((e) => parse(Map<String, dynamic>.from(e as Map))).toList();

/// Adds `X-App`, `X-App-Version`, `Accept-Language`.
class HeadersInterceptor extends Interceptor {
  HeadersInterceptor({required this.config, required this.languageCode});
  final AppConfig config;
  final String Function() languageCode;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-App'] = config.app.name;
    options.headers['X-App-Version'] = config.appVersion;
    options.headers['Accept-Language'] = languageCode();
    handler.next(options);
  }
}

/// Adds the bearer token; on `401 token_expired` refreshes once (shared
/// between concurrent requests) and retries; logs out if refresh fails.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.session, required this.dio, required this.refresh});
  final SessionStore session;
  final Dio dio;
  final Future<bool> Function() refresh;

  static const _retriedKey = 'auth_retried';
  static const _tokenKey = 'auth_token_used';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = session.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
      options.extra[_tokenKey] = token;
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final res = err.response;
    final opts = err.requestOptions;
    final isExpired = res?.statusCode == 401 && ApiException.fromResponse(401, res?.data).code == ErrorCodes.tokenExpired;
    if (!isExpired || opts.extra[_retriedKey] == true) return handler.next(err);

    // Another request may already have refreshed while this one was in flight.
    final usedToken = opts.extra[_tokenKey];
    final ok = (session.accessToken != null && session.accessToken != usedToken) ? true : await refresh();
    if (!ok) return handler.next(err);
    try {
      opts.extra[_retriedKey] = true;
      final response = await dio.fetch<Object?>(opts);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// Retries idempotent GETs up to 2 times on network errors / 5xx.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({required this.dio, this.maxRetries = 2, this.baseDelay = const Duration(milliseconds: 600)});
  final Dio dio;
  final int maxRetries;
  final Duration baseDelay;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final attempt = (opts.extra['retry_attempt'] as int?) ?? 0;
    final status = err.response?.statusCode;
    // 429: honour Retry-After once when the wait is short and the request is
    // safe to repeat (GET, or carries an Idempotency-Key).
    if (status == 429) {
      final wait = int.tryParse(err.response?.headers.value('retry-after') ?? '') ?? 2;
      final safe = opts.method == 'GET' || opts.headers.containsKey('Idempotency-Key');
      if (!safe || wait > 8 || opts.extra['rate_retried'] == true) return handler.next(err);
      opts.extra['rate_retried'] = true;
      await Future<void>.delayed(Duration(seconds: wait));
      try {
        handler.resolve(await dio.fetch<Object?>(opts));
      } on DioException catch (e) {
        handler.next(e);
      }
      return;
    }
    final retryable =
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        (status != null && status >= 500);
    if (opts.method != 'GET' || !retryable || attempt >= maxRetries) return handler.next(err);
    await Future<void>.delayed(baseDelay * (attempt + 1));
    opts.extra['retry_attempt'] = attempt + 1;
    try {
      handler.resolve(await dio.fetch<Object?>(opts));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}

/// Debug-only logging that never prints tokens.
class RedactingLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('→ ${options.method} ${options.path} ${options.queryParameters.isEmpty ? '' : options.queryParameters}');
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    debugPrint('← ${response.statusCode} ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint('✗ ${err.response?.statusCode ?? err.type.name} ${err.requestOptions.path}');
    handler.next(err);
  }
}
