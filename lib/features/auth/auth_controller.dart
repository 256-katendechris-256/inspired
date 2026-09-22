import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/config.dart';
import '../../core/notifications/push_service.dart';
import '../../core/notifications/reminder_service.dart';

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
      if (!user.mustChangePassword) {
        unawaited(PushService.instance.registerWithBackend(_dio));
        unawaited(ReminderService.instance.sync(_dio));
      }
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
      await _applyAuthResponse(Map<String, dynamic>.from(res.data));
    } on DioException catch (e) {
      throw AuthException(_detail(e, fallback: 'Unable to sign in. Try again.'));
    }
  }

  // Web talks to Google Identity Services directly, so it needs its own
  // browser-facing `clientId` (same OAuth client the backend verifies the
  // id_token audience against — see GOOGLE_OAUTH_CLIENT_ID). Mobile instead
  // uses `serverClientId` to request an id_token scoped to that same client
  // while signing in with the platform-native flow.
  final _googleSignIn = GoogleSignIn(
    scopes: const ['email'],
    clientId: kIsWeb && Config.googleWebClientId.isNotEmpty
        ? Config.googleWebClientId
        : null,
    serverClientId: !kIsWeb && Config.googleServerClientId.isNotEmpty
        ? Config.googleServerClientId
        : null,
  );

  StreamSubscription<GoogleSignInAccount?>? _googleUserSub;

  /// Web has no imperative sign-in entry point that reliably returns an
  /// idToken (see google_web_button_web.dart) — the rendered GIS button
  /// drives its own credential flow and reports the result on this stream
  /// instead. Subscribed once, lazily, only on web; mobile keeps using the
  /// direct await in [signInWithGoogle].
  void ensureGoogleWebListener() {
    if (!kIsWeb || _googleUserSub != null) return;
    _googleUserSub = _googleSignIn.onCurrentUserChanged.listen((account) async {
      if (account == null) return;
      try {
        await _exchangeGoogleAccount(account);
      } on AuthException {
        // Nothing awaits this stream — surfaced via LoginScreen's error
        // state would require plumbing a callback through; for now a failed
        // exchange here just leaves the user on the login screen, same as
        // dismissing the picker. Real failures (network, unregistered
        // email) are rare enough post-credential that this is an acceptable
        // gap rather than over-engineering a callback for it.
      }
    });
  }

  /// Google Sign-In — no password at all, first login or otherwise. Only
  /// works if HR/admin already pre-registered this Google account's email as
  /// an Employee (same check the backend does for the password path); a
  /// verified email with no matching record is rejected server-side with a
  /// "contact HR" message rather than silently creating an account.
  ///
  /// Mobile only — web signs in via the rendered button in
  /// google_web_button_web.dart, picked up by [ensureGoogleWebListener].
  Future<void> signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return; // user dismissed the account picker
    await _exchangeGoogleAccount(account);
  }

  /// Shared tail of both Google sign-in paths: trade the account's idToken
  /// for our own session tokens.
  Future<void> _exchangeGoogleAccount(GoogleSignInAccount account) async {
    try {
      final idToken = (await account.authentication).idToken;
      if (idToken == null) {
        throw AuthException('Google sign-in did not return a token. Try again.');
      }
      final res = await _dio.post(
        '/api/auth/google',
        data: {'id_token': idToken},
        options: Options(extra: _noAuth),
      );
      await _applyAuthResponse(Map<String, dynamic>.from(res.data));
    } on DioException catch (e) {
      await _googleSignIn.signOut();
      throw AuthException(_detail(e, fallback: 'Unable to sign in with Google.'));
    }
  }

  /// Shared tail of both login paths: persist tokens, derive [AuthState],
  /// and register for push once past any forced password reset.
  Future<void> _applyAuthResponse(Map<String, dynamic> data) async {
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
    if (!user.mustChangePassword) {
      unawaited(PushService.instance.registerWithBackend(_dio));
        unawaited(ReminderService.instance.sync(_dio));
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
      unawaited(PushService.instance.registerWithBackend(_dio));
        unawaited(ReminderService.instance.sync(_dio));
    } on DioException catch (e) {
      throw AuthException(_detail(e, fallback: 'Could not update your password.'));
    }
  }

  Future<void> logout() async {
    await PushService.instance.unregister(_dio);
    await ReminderService.instance.clear();
    await _clearTokens();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  @override
  void dispose() {
    _googleUserSub?.cancel();
    super.dispose();
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
