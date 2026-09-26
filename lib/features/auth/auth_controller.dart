import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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

  /// May see and vouch for a department roster — a HOD for their own people,
  /// System Admin for anyone's. Mirrors TEAM_ROLES on the server; the server
  /// enforces it, this only decides whether to offer the door.
  bool get managesTeam => role == 'hod' || role == 'admin';

  String get firstName {
    final first = fullName.trim().split(' ').first;
    return first.isEmpty ? 'there' : first;
  }

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    employeeId: json['employee_id'] as String? ?? '',
    fullName: json['full_name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    role: json['role'] as String? ?? 'employee',
    department: json['department'] as String? ?? '',
    mustChangePassword: json['must_change_password'] as bool? ?? false,
  );

  /// The same shape [fromJson] reads, for the cached profile.
  Map<String, dynamic> toJson() => {
    'employee_id': employeeId,
    'full_name': fullName,
    'email': email,
    'role': role,
    'department': department,
    'must_change_password': mustChangePassword,
  };

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

  /// Decide where to send the user on launch.
  ///
  /// Being offline is not being signed out. Anyone who signed in on this
  /// phone opens straight into the app from the profile cached at their last
  /// sign-in, and the session is checked with the server in the background.
  /// Only the server actually *rejecting* it (401/403 after a refresh
  /// attempt) signs them out — never a timeout, a dead zone, or a 502 while
  /// the backend redeploys. The refresh token slides, so daily users are
  /// never asked to sign in again.
  Future<void> bootstrap() async {
    final access = _prefs.getString(kAccessTokenKey);
    if (access == null || access.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    _tokens.accessToken = access;

    final known = _cachedUser() ?? _userFromToken(access);
    if (known != null) {
      state = _stateFor(known);
      unawaited(revalidation = _revalidate());
      return;
    }
    // Tokens but no idea who they belong to (should not happen): ask.
    await _revalidate();
    if (state.status == AuthStatus.unknown) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// The background session check started by [bootstrap], for tests.
  @visibleForTesting
  Future<void>? revalidation;

  AuthState _stateFor(AppUser user) => AuthState(
    status: user.mustChangePassword
        ? AuthStatus.mustResetPassword
        : AuthStatus.authenticated,
    user: user,
  );

  /// Confirm the session with the server and refresh the cached profile.
  Future<void> _revalidate() async {
    try {
      final res = await _dio.get('/api/auth/me');
      final user = AppUser.fromJson(Map<String, dynamic>.from(res.data));
      await _cacheUser(user);
      state = _stateFor(user);
      if (!user.mustChangePassword) {
        unawaited(PushService.instance.registerWithBackend(_dio));
        unawaited(ReminderService.instance.sync(_dio));
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        await _clearTokens();
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
      // Anything else — no signal, timeout, 5xx, 429 — keeps the session.
    }
  }

  /// A minimal profile read from the access token's own claims, for someone
  /// who signed in before the profile was cached. The next successful
  /// revalidation fills in their name.
  AppUser? _userFromToken(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final id = claims['employee_id'] as String?;
      if (id == null || id.isEmpty) return null;
      return AppUser(
        employeeId: id,
        fullName: '',
        email: claims['email'] as String? ?? '',
        role: claims['role'] as String? ?? 'employee',
        department: claims['dept_code'] as String? ?? '',
        mustChangePassword: false,
      );
    } catch (_) {
      return null;
    }
  }

  static const _kCachedUser = 'inspired.user.v1';

  Future<void> _cacheUser(AppUser user) =>
      _prefs.setString(_kCachedUser, jsonEncode(user.toJson()));

  AppUser? _cachedUser() {
    final raw = _prefs.getString(_kCachedUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AppUser.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
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
    // Cache now, not at the next launch: otherwise the first time someone
    // opens the app without signal after signing in, there is no profile to
    // open with.
    await _cacheUser(user);
    state = _stateFor(user);
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
      await _cacheUser(user);
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
    await _prefs.remove(_kCachedUser);
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
