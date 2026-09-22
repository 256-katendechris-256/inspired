import 'package:flutter/widgets.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart' as web;

/// Renders Google's own Sign-In-With-Google button via the GIS credential
/// flow (`google.accounts.id`), which — unlike the deprecated imperative
/// `GoogleSignIn().signIn()` popup flow on web — actually returns an
/// idToken. See auth_controller.dart's `_googleSignIn.onCurrentUserChanged`
/// listener for where the resulting credential is picked up.
///
/// `renderButton` lives on the concrete web plugin class, not the shared
/// `GoogleSignInPlatform` interface, so the singleton has to be cast.
Widget buildGoogleWebButton() {
  final platform = GoogleSignInPlatform.instance;
  if (platform is web.GoogleSignInPlugin) {
    return platform.renderButton(
      configuration: web.GSIButtonConfiguration(
        type: web.GSIButtonType.standard,
        theme: web.GSIButtonTheme.outline,
        size: web.GSIButtonSize.large,
        text: web.GSIButtonText.continueWith,
        shape: web.GSIButtonShape.rectangular,
      ),
    );
  }
  return const SizedBox.shrink();
}
