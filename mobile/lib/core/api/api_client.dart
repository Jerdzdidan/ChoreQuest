import 'dart:io';

import 'package:dio/dio.dart';

import '../config.dart';
import 'api_exception.dart';

/// Supplies the bearer token for a request, or null when nobody is signed in.
typedef TokenReader = Future<String?> Function();

/// The only place the app speaks HTTP.
///
/// Every failure leaves this class as an [ApiException] carrying a message fit
/// to show, so no screen ever needs to know what a DioException or a status
/// code is.
class ApiClient {
  ApiClient({required TokenReader readToken, Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: AppConfig.connectTimeout,
                receiveTimeout: AppConfig.receiveTimeout,
                headers: {'Accept': 'application/json'},
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await readToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) =>
      _send(() => _dio.get<Object?>(_url(path), queryParameters: query));

  Future<Map<String, dynamic>> post(String path, {Object? body}) =>
      _send(() => _dio.post<Object?>(_url(path), data: body));

  Future<Map<String, dynamic>> patch(String path, {Object? body}) =>
      _send(() => _dio.patch<Object?>(_url(path), data: body));

  Future<Map<String, dynamic>> delete(String path) =>
      _send(() => _dio.delete<Object?>(_url(path)));

  /// Absolute URLs rather than Dio's baseUrl, so there is no ambiguity about
  /// whether a leading slash appends to the /api prefix or replaces it.
  String _url(String path) => '${AppConfig.apiBaseUrl}$path';

  Future<Map<String, dynamic>> _send(
    Future<Response<Object?>> Function() call,
  ) async {
    try {
      final response = await call();
      final data = response.data;
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  ApiException _translate(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return const ApiUnreachable();
      case DioExceptionType.badResponse:
        return _fromResponse(e.response);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return e.error is SocketException
            ? const ApiUnreachable()
            : const ApiServerError();
    }
  }

  ApiException _fromResponse(Response<Object?>? response) {
    final status = response?.statusCode ?? 0;
    final body = response?.data;
    final json = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final message = json['message'] is String ? json['message'] as String : null;

    return switch (status) {
      401 => const ApiUnauthorised(),
      403 => const ApiForbidden(),
      423 => ApiLocked(
          message ?? 'Too many tries. Ask a grown-up to help.',
          lockedUntil: DateTime.tryParse('${json['locked_until'] ?? ''}'),
        ),
      429 => const ApiLocked(
          'Too many tries in a row. Wait a minute, then try again.',
        ),
      >= 500 => const ApiServerError(),
      _ => ApiRejected(
          message ?? 'That request was turned down.',
          statusCode: status,
          fieldErrors: _fieldErrors(json['errors']),
        ),
    };
  }

  static Map<String, List<String>> _fieldErrors(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        '${entry.key}': [
          if (entry.value is List)
            for (final message in entry.value as List) '$message',
        ],
    };
  }
}
