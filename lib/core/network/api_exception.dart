import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.isNetwork = false});

  final String message;
  final int? statusCode;

  /// True when the server could not be reached (offline, DNS, timeout).
  final bool isNetwork;

  /// 4xx other than auth/timeouts: retrying the same payload will not help.
  bool get isPermanent => statusCode != null && statusCode! >= 400 && statusCode! < 500 && statusCode != 401 && statusCode != 408 && statusCode != 429;

  factory ApiException.fromDio(DioException e) {
    final response = e.response;
    if (response == null) {
      return ApiException(
        e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout
            ? 'The server took too long to respond'
            : 'Cannot reach the Zaam server',
        isNetwork: true,
      );
    }
    final data = response.data;
    String? message;
    if (data is Map && data['error'] is Map) message = (data['error'] as Map)['message']?.toString();
    if (data is Map && message == null) message = data['message']?.toString();
    return ApiException(message ?? 'Request failed (${response.statusCode})', statusCode: response.statusCode);
  }

  @override
  String toString() => message;
}

String errorMessage(Object error) {
  if (error is ApiException) return error.message;
  if (error is DioException) return ApiException.fromDio(error).message;
  return error.toString().replaceFirst('Exception: ', '');
}
