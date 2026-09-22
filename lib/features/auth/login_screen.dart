import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/brand.dart';
import 'auth_controller.dart';
import 'google_web_button_stub.dart'
    if (dart.library.html) 'google_web_button_web.dart'
    as google_web;

enum _Step { email, credentials }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _employeeId = TextEditingController();
  final _password = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Web's Google button drives its own credential flow outside of any
    // button onPressed here (see google_web_button_web.dart) — this picks
    // up the result. No-op on mobile.
    if (kIsWeb) {
      Future.microtask(
        () => ref.read(authControllerProvider.notifier).ensureGoogleWebListener(),
      );
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _employeeId.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueWithEmail() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter the work email your admin registered.');
      return;
    }
    await _run(() async {
      await ref.read(authControllerProvider.notifier).checkEmail(email);
      if (mounted) setState(() => _step = _Step.credentials);
    });
  }

  Future<void> _continueWithGoogle() async {
    await _run(() async {
      await ref.read(authControllerProvider.notifier).signInWithGoogle();
      if (!mounted) return;
      final status = ref.read(authControllerProvider).status;
      if (status == AuthStatus.unauthenticated) return; // picker was dismissed
      context.go(
        status == AuthStatus.mustResetPassword ? '/reset-password' : '/home',
      );
    });
  }

  Future<void> _signIn() async {
    if (_employeeId.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your employee ID and password.');
      return;
    }
    await _run(() async {
      await ref
          .read(authControllerProvider.notifier)
          .login(
            email: _email.text,
            employeeId: _employeeId.text,
            password: _password.text,
          );
      if (!mounted) return;
      final status = ref.read(authControllerProvider).status;
      context.go(
        status == AuthStatus.mustResetPassword ? '/reset-password' : '/home',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmailStep = _step == _Step.email;

    // Web's rendered Google button signs in outside of _continueWithGoogle's
    // await chain (see initState), so navigation on success has to react to
    // the resulting state change instead of following a direct call.
    // Harmless no-op for the mobile flow, which already navigates itself.
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (!kIsWeb) return;
      if (next.status == AuthStatus.authenticated) {
        context.go('/home');
      } else if (next.status == AuthStatus.mustResetPassword) {
        context.go('/reset-password');
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(Brand.markAsset, height: 104),
                  const SizedBox(height: 20),
                  Text(
                    'Inspire Africa',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Brand.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isEmailStep
                        ? 'Sign in with the work email your administrator registered.'
                        : 'Enter your employee ID and the password you were given.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Brand.slate,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (isEmailStep) ..._emailStep() else ..._credentialStep(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _ErrorBanner(_error!),
                  ],
                  const SizedBox(height: 28),
                  Text(
                    'Employee portal',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Brand.slate,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _emailStep() => [
    if (kIsWeb)
      // The real Google-branded button — required for the GIS credential
      // flow that actually returns an idToken on web (see
      // google_web_button_web.dart). Its own internal click handler drives
      // sign-in; nothing here calls _continueWithGoogle.
      Center(child: google_web.buildGoogleWebButton())
    else
      OutlinedButton.icon(
        onPressed: _busy ? null : _continueWithGoogle,
        icon: const Icon(Icons.g_mobiledata, size: 26),
        label: const Text('Continue with Google'),
      ),
    const SizedBox(height: 18),
    Row(
      children: [
        Expanded(child: Divider(color: Brand.line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('or', style: TextStyle(color: Brand.mute, fontSize: 12)),
        ),
        Expanded(child: Divider(color: Brand.line)),
      ],
    ),
    const SizedBox(height: 18),
    TextField(
      controller: _email,
      enabled: !_busy,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.email],
      onSubmitted: (_) => _continueWithEmail(),
      decoration: const InputDecoration(
        labelText: 'Work email',
        prefixIcon: Icon(Icons.mail_outline),
      ),
    ),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: _busy ? null : _continueWithEmail,
      child: _busy ? const _Spinner() : const Text('Continue with employee ID'),
    ),
  ];

  List<Widget> _credentialStep() => [
    _EmailChip(email: _email.text.trim(), onChange: _busy ? null : _backToEmail),
    const SizedBox(height: 16),
    TextField(
      controller: _employeeId,
      enabled: !_busy,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'Employee ID',
        prefixIcon: Icon(Icons.badge_outlined),
      ),
    ),
    const SizedBox(height: 14),
    TextField(
      controller: _password,
      enabled: !_busy,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _signIn(),
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    ),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: _busy ? null : _signIn,
      child: _busy ? const _Spinner() : const Text('Sign in'),
    ),
  ];

  void _backToEmail() => setState(() {
    _step = _Step.email;
    _error = null;
    _password.clear();
  });
}

class _EmailChip extends StatelessWidget {
  const _EmailChip({required this.email, required this.onChange});
  final String email;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Brand.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(email, overflow: TextOverflow.ellipsis),
          ),
          TextButton(onPressed: onChange, child: const Text('Change')),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Brand.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(color: Brand.red)),
          ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 22,
    width: 22,
    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
  );
}
