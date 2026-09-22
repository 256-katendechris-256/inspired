import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/brand.dart';
import '../features/attendance/attendance_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/home/home_screen.dart';
import '../features/leave/leave_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/requests/finance_requisition_screen.dart';
import '../features/requests/requests_hub_screen.dart';
import '../features/requests/store_request_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/tasks/tasks_screen.dart';

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
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),
      GoRoute(path: '/history', builder: (_, _) => const AttendanceScreen()),
      GoRoute(path: '/tasks', builder: (_, _) => const TasksScreen()),
      GoRoute(path: '/requests', builder: (_, _) => const RequestsHubScreen()),
      GoRoute(path: '/requests/leave', builder: (_, _) => const LeaveScreen()),
      GoRoute(
        path: '/requests/store',
        builder: (_, _) => const StoreRequestScreen(),
      ),
      GoRoute(
        path: '/requests/finance',
        builder: (_, _) => const FinanceRequisitionScreen(),
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
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
    ],
  );
});
