import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Persisted JWT keys.
const kAccessTokenKey = 'inspired.access';
const kRefreshTokenKey = 'inspired.refresh';

/// Overridden in main() with the resolved instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

/// Holds the access token in memory so authenticated requests never depend on
/// a per-request disk read.
class AuthTokenStore {
  String? accessToken;
}

final authTokenStoreProvider = Provider<AuthTokenStore>(
  (ref) => AuthTokenStore(),
);

final dioProvider = Provider<Dio>((ref) {
  final tokens = ref.watch(authTokenStoreProvider);
  final prefs = ref.watch(sharedPreferencesProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: Config.backendUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  // One refresh in flight at a time: when the access token lapses, every
  // screen's request 401s together, and they should all wait on the same
  // refresh rather than fire N of them.
  Future<String?>? refreshing;

  Future<String?> refreshAccess() async {
    final refresh = prefs.getString(kRefreshTokenKey);
    if (refresh == null || refresh.isEmpty) return null;
    // A bare Dio so the expired token isn't attached and we don't recurse
    // through this interceptor. A network failure here propagates — the
    // caller must not mistake "couldn't reach the server" for "signed out".
    final res = await Dio(
      BaseOptions(
        baseUrl: Config.backendUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    ).post('/api/auth/refresh', data: {'refresh': refresh});
    final newAccess = res.data['access'] as String;
    tokens.accessToken = newAccess;
    await prefs.setString(kAccessTokenKey, newAccess);
    // The server slides the session by issuing a fresh refresh token.
    final newRefresh = res.data['refresh'];
    if (newRefresh is String && newRefresh.isNotEmpty) {
      await prefs.setString(kRefreshTokenKey, newRefresh);
    }
    return newAccess;
  }

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.extra['auth'] != false) {
          final token = tokens.accessToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        final opts = e.requestOptions;
        final is401 = e.response?.statusCode == 401;
        final eligible = opts.extra['auth'] != false &&
            opts.extra['retried'] != true;
        if (!is401 || !eligible) return handler.next(e);

        String? newAccess;
        try {
          newAccess = await (refreshing ??= refreshAccess().whenComplete(
            () => refreshing = null,
          ));
        } on DioException catch (refreshError) {
          if (refreshError.response == null) {
            // Offline mid-refresh: surface it as a connection problem, so
            // nothing downstream treats the stale 401 as a revoked session.
            return handler.next(refreshError);
          }
          // The server refused the refresh token → genuinely signed out.
          return handler.next(e);
        } catch (_) {
          return handler.next(e);
        }
        if (newAccess == null) return handler.next(e);

        try {
          opts.headers['Authorization'] = 'Bearer $newAccess';
          opts.extra['retried'] = true;
          // A multipart body is a one-shot stream; re-send a fresh copy.
          if (opts.data is FormData) opts.data = (opts.data as FormData).clone();
          return handler.resolve(await dio.fetch(opts));
        } on DioException catch (retryError) {
          return handler.next(retryError);
        }
      },
    ),
  );

  return dio;
});
