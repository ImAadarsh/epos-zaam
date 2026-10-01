import 'package:dio/dio.dart';

import 'api_exception.dart';

typedef TokenReader = ({String? access, String? refresh}) Function();

/// Thin wrapper over Dio for the Zaam API.
///
/// Adds the bearer token, refreshes it once on 401 via
/// `POST /api/iam/auth/refresh`, and converts failures to [ApiException].
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required TokenReader tokens,
    required void Function(String accessToken) onRefreshed,
    required void Function() onUnauthorized,
  })  : _tokens = tokens,
        _onRefreshed = onRefreshed,
        _onUnauthorized = onUnauthorized {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ));
    dio.interceptors.add(QueuedInterceptorsWrapper(
      onRequest: (options, handler) {
        final access = _tokens().access;
        if (access != null && options.headers['Authorization'] == null) {
          options.headers['Authorization'] = 'Bearer $access';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final isAuthCall = error.requestOptions.path.contains('/iam/auth/');
        if (error.response?.statusCode == 401 && !isAuthCall && error.requestOptions.extra['retried'] != true) {
          final fresh = await _refresh();
          if (fresh != null) {
            final opts = error.requestOptions
              ..headers['Authorization'] = 'Bearer $fresh'
              ..extra['retried'] = true;
            try {
              handler.resolve(await dio.fetch(opts));
              return;
            } on DioException catch (e) {
              handler.next(e);
              return;
            }
          }
          _onUnauthorized();
        }
        handler.next(error);
      },
    ));
  }

  final String baseUrl;
  final TokenReader _tokens;
  final void Function(String accessToken) _onRefreshed;
  final void Function() _onUnauthorized;
  late final Dio dio;

  Future<String?> _refresh() async {
    final refresh = _tokens().refresh;
    if (refresh == null) return null;
    try {
      final res = await Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10)))
          .post('/api/iam/auth/refresh', data: {'refreshToken': refresh});
      final token = (res.data as Map)['accessToken'] as String?;
      if (token != null) _onRefreshed(token);
      return token;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => dio.get(path, queryParameters: _clean(query)));

  Future<dynamic> post(String path, {Object? data}) => _wrap(() => dio.post(path, data: data));

  Future<dynamic> put(String path, {Object? data}) => _wrap(() => dio.put(path, data: data));

  Future<dynamic> patch(String path, {Object? data}) => _wrap(() => dio.patch(path, data: data));

  Future<dynamic> delete(String path) => _wrap(() => dio.delete(path));

  /// Lightweight reachability probe used by the connectivity monitor.
  Future<bool> ping() async {
    try {
      final res = await dio.get('/health', options: Options(sendTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _wrap(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      return res.data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  static Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    return Map.fromEntries(q.entries.where((e) => e.value != null && e.value.toString().isNotEmpty));
  }
}
