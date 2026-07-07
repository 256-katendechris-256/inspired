import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';

/// The signed-in employee, decoded from the auth response.
class AppUser {
  const AppUser({
    required this.employeeId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.department,
    required this.mustChangePassword,
  });

  final String employeeId;
  final String fullName;
  final String email;
  final String role; // employee | hod | hr | admin | exec
  final String department;
  final bool mustChangePassword;

  bool get isHod => role == 'hod';

  String get firstName => fullName.split(' ').first;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    employeeId: json['employee_id'] as String? ?? '',
    fullName: json['full_name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    role: json['role'] as String? ?? 'employee',
    department: json['department'] as String? ?? '',
    mustChangePassword: json['must_change_password'] as bool? ?? false,
  );

  AppUser copyWith({bool? mustChangePassword}) => AppUser(
    employeeId: employeeId,
    fullName: fullName,
    email: email,
    role: role,
    department: department,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
  );
}

enum AuthStatus { unknown, unauthenticated, mustResetPassword, authenticated }

class AuthState {
  const AuthState({this.status = AuthStatus.unknown, this.user});

  final AuthStatus status;
  final AppUser? user;

  AuthState copyWith({AuthStatus? status, AppUser? user}) =>
      AuthState(status: status ?? this.status, user: user ?? this.user);
}

/// Friendly, user-facing failure surfaced to the UI.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
      return AuthController(
        dio: ref.watch(dioProvider),
        prefs: ref.watch(sharedPreferencesProvider),
        tokens: ref.watch(authTokenStoreProvider),
      );
    });

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required Dio dio,
    required SharedPreferences prefs,
    required AuthTokenStore tokens,
  }) : _dio = dio,
       _prefs = prefs,
       _tokens = tokens,
       super(const AuthState());

  final Dio _dio;
  final SharedPreferences _prefs;
  final AuthTokenStore _tokens;

  static const _noAuth = {'auth': false};

  /// Decide where to send the user on launch. The persisted access token is
  /// loaded into memory; the /me call auto-refreshes via the Dio interceptor
  /// if the access token has expired, so sessions survive app restarts.
  Future<void> bootstrap() async {
    final access = _prefs.getString(kAccessTokenKey);
    if (access == null || access.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    _tokens.accessToken = access;
    try {
      final res = await _dio.get('/api/auth/me');
      final user = AppUser.fromJson(Map<String, dynamic>.from(res.data));
      state = AuthState(
        status: user.mustChangePassword
            ? AuthStatus.mustResetPassword
            : AuthStatus.authenticated,
        user: user,
      );
    } on DioException {
      await _clearTokens();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Step 1 — is this email pre-registered by an admin?
  /// Returns normally if recognised; throws [AuthException] otherwise.
  Future<void> checkEmail(String email) async {
    try {
      await _dio.post(
        '/api/auth/login/check-email',
        data: {'email': email.trim()},
        options: Options(extra: _noAuth),
      );
    } on DioException catch (e) {
      throw AuthException(_detail(e, fallback: 'We couldn\'t verify that email.'));
    }
  }

  /// Step 2 — employee ID + preset password. Stores tokens and moves to the
  /// reset screen (if required) or home.
  Future<void> login({
    required String email,
    required String employeeId,
    required String password,
  }) async {
    try {
      final res = await _dio.post(
        '/api/auth/login',
        data: {
          'email': email.trim(),
          'employee_id': employeeId.trim(),
          'password': password,
        },
        options: Options(extra: _noAuth),
      );
      final data = Map<String, dynamic>.from(res.data);
      // In-memory first: authenticated requests rely on this, not on disk.
      _tokens.accessToken = data['access'] as String;
      // Persist both tokens so the session survives app restarts.
      await _prefs.setString(kAccessTokenKey, data['access'] as String);
      await _prefs.setString(kRefreshTokenKey, data['refresh'] as String);
      final user = AppUser.fromJson(Map<String, dynamic>.from(data['employee']));
      state = AuthState(
        status: user.mustChangePassword
            ? AuthStatus.mustResetPassword
            : AuthStatus.authenticated,
        user: user,
      );
    } on DioException catch (e) {
      throw AuthException(_detail(e, fallback: 'Unable to sign in. Try again.'));
    }
  }

  /// Forced first-login reset (and ordinary changes later).
  Future<void> setNewPassword(String newPassword) async {
    try {
      final res = await _dio.post(
        '/api/auth/set-password',
        data: {'new_password': newPassword},
      );
      final user = AppUser.fromJson(
        Map<String, dynamic>.from(res.data['employee']),
      );
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on DioException catch (e) {
      throw AuthException(_detail(e, fallback: 'Could not update your password.'));
    }
  }

  Future<void> logout() async {
    await _clearTokens();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> _clearTokens() async {
    _tokens.accessToken = null;
    await _prefs.remove(kAccessTokenKey);
    await _prefs.remove(kRefreshTokenKey);
  }

  String _detail(DioException e, {required String fallback}) {
    // No response at all → the server was unreachable (wrong BACKEND_URL,
    // backend down, or cleartext blocked). Say so plainly rather than blaming
    // the user's input.
    if (e.response == null) {
      return 'Can\'t reach the server. Check your connection and try again.';
    }
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return fallback;
  }
}
