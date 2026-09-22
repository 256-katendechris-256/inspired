import 'package:flutter/widgets.dart';

/// Non-web platforms never render this — [LoginScreen] gates on `kIsWeb` and
/// keeps the native `GoogleSignIn().signIn()` button there instead. This stub
/// only exists so the conditional import in login_screen.dart has something
/// to resolve to on Android/iOS without pulling in google_sign_in_web (a
/// web-only package that won't compile for those targets).
Widget buildGoogleWebButton() => const SizedBox.shrink();
