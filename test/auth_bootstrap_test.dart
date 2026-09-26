import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inspired/core/api/api_client.dart';
import 'package:inspired/features/auth/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers every request with one scripted outcome: a status code + body,
/// or (status 0) a dropped connection, as in a dead zone.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.status, [this.body = const {}]);
  final int status;
  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (status == 0) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no signal',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _jwt(Map<String, dynamic> claims) {
  String part(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(claims)}.sig';
}

const _profile = {
  'employee_id': 'PROD-002',
  'full_name': 'Jane Achieng',
  'email': 'jane@example.com',
  'role': 'employee',
  'department': 'PROD',
  'must_change_password': false,
};

Future<(AuthController, SharedPreferences)> _controller(
  _ScriptedAdapter adapter,
  Map<String, Object> stored,
) async {
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  // No interceptor here: these responses aren't 401s, so the refresh path
  // (covered separately) never runs.
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter;
  return (AuthController(dio: dio, prefs: prefs, tokens: AuthTokenStore()), prefs);
}

void main() {
  final signedIn = <String, Object>{
    kAccessTokenKey: 'access',
    kRefreshTokenKey: 'refresh',
    'inspired.user.v1': jsonEncode(_profile),
  };

  test('opening the app with no signal keeps you signed in', () async {
    final (auth, prefs) = await _controller(_ScriptedAdapter(0), signedIn);
    await auth.bootstrap();
    await auth.revalidation; // the background check with the server
    expect(auth.state.status, AuthStatus.authenticated);
    expect(auth.state.user?.firstName, 'Jane');
    expect(prefs.getString(kRefreshTokenKey), 'refresh');
  });

  test('a server error while the backend redeploys keeps you signed in', () async {
    final (auth, prefs) = await _controller(_ScriptedAdapter(503), signedIn);
    await auth.bootstrap();
    await auth.revalidation;
    expect(auth.state.status, AuthStatus.authenticated);
    expect(prefs.getString(kAccessTokenKey), 'access');
  });

  test('signed in before the profile was cached: rebuilt from the token', () async {
    final token = _jwt({'employee_id': 'PROD-002', 'role': 'hod', 'dept_code': 'PROD'});
    final (auth, _) = await _controller(_ScriptedAdapter(0), {
      kAccessTokenKey: token,
      kRefreshTokenKey: 'refresh',
    });
    await auth.bootstrap();
    expect(auth.state.status, AuthStatus.authenticated);
    expect(auth.state.user?.employeeId, 'PROD-002');
    expect(auth.state.user?.managesTeam, isTrue);
    expect(auth.state.user?.firstName, 'there');
  });

  test('the server revoking the session signs you out', () async {
    final (auth, prefs) = await _controller(
      _ScriptedAdapter(403, {'detail': 'inactive'}),
      signedIn,
    );
    await auth.bootstrap();
    await auth.revalidation;
    expect(auth.state.status, AuthStatus.unauthenticated);
    expect(prefs.getString(kAccessTokenKey), isNull);
    expect(prefs.getString('inspired.user.v1'), isNull);
  });

  test('signing in caches the profile for the next offline launch', () async {
    final (auth, prefs) = await _controller(
      _ScriptedAdapter(200, {
        'access': 'a',
        'refresh': 'r',
        'employee': {..._profile, 'must_change_password': true},
      }),
      {},
    );
    await auth.login(email: 'jane@example.com', employeeId: 'PROD-002', password: 'x');
    expect(prefs.getString('inspired.user.v1'), contains('Jane Achieng'));
  });
}
