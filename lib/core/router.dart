import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/brand.dart';
import '../features/attendance/attendance_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/home/home_screen.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../features/splash/splash_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const ResetPasswordScreen(),
      ),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/history', builder: (_, _) => const AttendanceScreen()),
      GoRoute(
        path: '/tasks',
        builder: (_, _) => const PlaceholderScreen(
          title: 'Tasks',
          icon: Icons.checklist_rtl,
          color: Brand.blue,
          blurb: 'See and update the work assigned to you by your supervisor.',
        ),
      ),
      GoRoute(
        path: '/requests',
        builder: (_, _) => const PlaceholderScreen(
          title: 'Requests',
          icon: Icons.outbox_outlined,
          color: Brand.orange,
          blurb: 'Submit leave and other requests, and track their approval.',
        ),
      ),
      GoRoute(
        path: '/reports',
        builder: (_, _) => const PlaceholderScreen(
          title: 'Reports',
          icon: Icons.insights_outlined,
          color: Brand.blue,
          blurb: 'Your attendance hours, site visits and monthly summaries.',
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const PlaceholderScreen(
          title: 'Profile',
          icon: Icons.person_outline,
          color: Brand.green,
          blurb: 'Your staff details, department and account settings.',
        ),
      ),
    ],
  );
});
