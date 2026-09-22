import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/api_client.dart';
import 'core/router.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // google-services.json (Android) supplies the config; no explicit options
  // needed here. Push registration is still best-effort even if this ever
  // fails (e.g. misconfigured project) — see PushService.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // App still works without push if Firebase init fails.
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const InspiredApp(),
    ),
  );
}

class InspiredApp extends ConsumerWidget {
  const InspiredApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Inspire Africa',
      debugShowCheckedModeBanner: false,
      theme: inspiredLightTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
