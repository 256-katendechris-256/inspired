import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Requests notification permission, resolves this device's FCM token, and
/// keeps the backend's record of it in sync so push (e.g. sign-out
/// reminders) can actually reach this device. Also renders foreground
/// pushes as a local notification, since FCM alone doesn't show a system
/// notification while the app is in the foreground on Android.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  static const _channel = AndroidNotificationChannel(
    'inspired_default',
    'Inspire Africa',
    description: 'Attendance and leave reminders.',
    importance: Importance.high,
  );

  final _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _lastRegisteredToken;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _local.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    });
  }

  /// Call after a successful login (and on app start while already signed
  /// in) so the backend always has this device's current token.
  Future<void> registerWithBackend(Dio dio) async {
    try {
      await _ensureInitialized();
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token == _lastRegisteredToken) return;

      await dio.post(
        '/api/notifications/devices',
        data: {
          'fcm_token': token,
          'platform': defaultTargetPlatform == TargetPlatform.iOS
              ? 'ios'
              : 'android',
        },
      );
      _lastRegisteredToken = token;
    } catch (_) {
      // Push registration is best-effort — never block sign-in on it.
    }
  }

  /// Best-effort cleanup on sign-out so a stale token doesn't linger.
  Future<void> unregister(Dio dio) async {
    final token = _lastRegisteredToken;
    if (token == null) return;
    try {
      await dio.delete('/api/notifications/devices', data: {'fcm_token': token});
    } catch (_) {
      // Fine to leave it registered if this fails — it just won't get pruned.
    } finally {
      _lastRegisteredToken = null;
    }
  }
}
