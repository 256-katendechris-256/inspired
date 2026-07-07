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

        if (is401 && eligible) {
          final refresh = prefs.getString(kRefreshTokenKey);
          if (refresh != null && refresh.isNotEmpty) {
            try {
              // Use a bare Dio so the (expired) token isn't attached and we
              // don't recurse through this interceptor.
              final res = await Dio(
                BaseOptions(baseUrl: Config.backendUrl),
              ).post('/api/auth/refresh', data: {'refresh': refresh});
              final newAccess = res.data['access'] as String;
              tokens.accessToken = newAccess;
              await prefs.setString(kAccessTokenKey, newAccess);

              opts.headers['Authorization'] = 'Bearer $newAccess';
              opts.extra['retried'] = true;
              final retried = await dio.fetch(opts);
              return handler.resolve(retried);
            } catch (_) {
              // Refresh failed → fall through, caller will see the 401.
            }
          }
        }
        handler.next(e);
      },
    ),
  );

  return dio;
});
