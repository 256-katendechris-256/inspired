import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import '../auth/auth_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    await ref.read(authControllerProvider.notifier).bootstrap();
    if (!mounted) return;
    switch (ref.read(authControllerProvider).status) {
      case AuthStatus.authenticated:
        context.go('/home');
      case AuthStatus.mustResetPassword:
        context.go('/reset-password');
      case AuthStatus.unauthenticated:
      case AuthStatus.unknown:
        context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(Brand.markAsset, height: 132),
            const SizedBox(height: 32),
            const SizedBox(
              height: 26,
              width: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6, color: Brand.green),
            ),
          ],
        ),
      ),
    );
  }
}
