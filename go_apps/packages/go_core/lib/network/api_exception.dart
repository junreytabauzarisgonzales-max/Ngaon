import 'package:dio/dio.dart';

/// Error codes from the API contract (Section 7.1) plus client-side ones.
class ErrorCodes {
  ErrorCodes._();
  static const validationFailed = 'validation_failed';
  static const tokenExpired = 'token_expired';
  static const unauthorized = 'unauthorized';
  static const forbidden = 'forbidden';
  static const notFound = 'not_found';
  static const otpInvalid = 'otp_invalid';
  static const otpExpired = 'otp_expired';
  static const rateLimited = 'rate_limited';
  static const outOfServiceArea = 'out_of_service_area';
  static const merchantClosed = 'merchant_closed';
  static const itemUnavailable = 'item_unavailable';
  static const quoteExpired = 'quote_expired';
  static const jobNotCancellable = 'job_not_cancellable';
  static const invalidStatusTransition = 'invalid_status_transition';
  static const insufficientBalance = 'insufficient_balance';
  static const riderNotApproved = 'rider_not_approved';
  static const offerExpired = 'offer_expired';
  static const orderAlreadyHandled = 'order_already_handled';
  static const paymentFailed = 'payment_failed';
  static const serverError = 'server_error';

  // client-side only
  static const network = 'network';
  static const timeout = 'timeout';
  static const unknown = 'unknown';
}

/// Typed form of the error envelope
/// `{ "error": { "code", "message", "fields" } }`.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.fields = const {}, this.httpStatus});

  final String code;
  final String message;
  final Map<String, String> fields;
  final int? httpStatus;

  bool get isNetwork => code == ErrorCodes.network || code == ErrorCodes.timeout;

  static ApiException fromDio(DioException e) {
    if (e.error is ApiException) return e.error as ApiException;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException(ErrorCodes.timeout, 'Request timed out');
      case DioExceptionType.connectionError:
        return ApiException(ErrorCodes.network, 'No connection');
      default:
        break;
    }
    final res = e.response;
    if (res != null) return fromResponse(res.statusCode, res.data);
    if (e.error is Exception && e.type == DioExceptionType.unknown) {
      return ApiException(ErrorCodes.network, 'No connection');
    }
    return ApiException(ErrorCodes.unknown, e.message ?? 'Unknown error');
  }

  static ApiException fromResponse(int? status, Object? body) {
    if (body is Map && body['error'] is Map) {
      final err = body['error'] as Map;
      final fields = <String, String>{};
      if (err['fields'] is Map) {
        (err['fields'] as Map).forEach((k, v) => fields['$k'] = '$v');
      }
      return ApiException('${err['code'] ?? ErrorCodes.unknown}', '${err['message'] ?? ''}', fields: fields, httpStatus: status);
    }
    final code = (status ?? 500) >= 500 ? ErrorCodes.serverError : ErrorCodes.unknown;
    return ApiException(code, 'HTTP $status', httpStatus: status);
  }

  @override
  String toString() => 'ApiException($code, $message, $fields, $httpStatus)';
}
