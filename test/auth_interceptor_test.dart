import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inspired/core/api/api_client.dart';

/// Captures the outgoing request headers and returns a canned 200, so we can
/// assert what the auth interceptor attached — no real network, no storage.
class _RecordingAdapter implements HttpClientAdapter {
  String? capturedAuth;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedAuth = options.headers['Authorization'] as String?;
    return ResponseBody.fromString(
      '{"detail":"ok"}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late ProviderContainer container;
  late Dio dio;
  late _RecordingAdapter adapter;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    dio = container.read(dioProvider);
    adapter = _RecordingAdapter();
    dio.httpClientAdapter = adapter;
  });

  tearDown(() => container.dispose());

  test('authenticated request gets Bearer token from the in-memory store', () async {
    container.read(authTokenStoreProvider).accessToken = 'TESTTOKEN';

    await dio.post('/api/auth/set-password', data: {'new_password': 'x'});

    expect(adapter.capturedAuth, 'Bearer TESTTOKEN');
  });

  test('login (extra auth=false) sends no Authorization header', () async {
    container.read(authTokenStoreProvider).accessToken = 'TESTTOKEN';

    await dio.post(
      '/api/auth/login',
      data: {},
      options: Options(extra: {'auth': false}),
    );

    expect(adapter.capturedAuth, isNull);
  });

  test('no token => request still sends, just without a Bearer header', () async {
    await dio.post('/api/auth/set-password', data: {'new_password': 'x'});

    expect(adapter.capturedAuth, isNull);
  });
}
