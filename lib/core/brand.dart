import 'package:flutter/material.dart';

/// Inspire Africa Group brand palette, sampled directly from the logo
/// (images/Inspire.png). Green leads; orange / blue / red are accents used to
/// colour-code features.
abstract final class Brand {
  static const Color green = Color(0xFF00843A); // primary
  static const Color orange = Color(0xFFF5821E);
  static const Color blue = Color(0xFF0089CE);
  static const Color red = Color(0xFFE01B1B);

  static const Color ink = Color(0xFF111815); // near-black text
  static const Color slate = Color(0xFF5B6B62); // muted text
  static const Color mute = Color(0xFF8A968F); // tertiary / captions
  static const Color canvas = Color(0xFFF5F7F6); // app background
  static const Color surfaceAlt = Color(0xFFF0F3F1); // subtle fills / hovers
  static const Color line = Color(0xFFE7EBE9); // hairline borders

  /// Soft tint of the brand green for highlighted surfaces.
  static const Color greenWash = Color(0xFFEAF4EE);

  /// Full logo with wordmark — used as the launcher icon source.
  static const String logoAsset = 'images/Inspire.png';

  /// Just the Africa map (transparent, no text) — used for in-app icon spots.
  static const String markAsset = 'images/africa_mark.png';

  /// Accent rotation for feature tiles / category chips.
  static const List<Color> accents = <Color>[green, orange, blue, red];

  // --- Depth & dimensionality ------------------------------------------------

  /// Signature brand gradient for hero surfaces (vivid → deep green).
  static const LinearGradient greenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF12A656), Color(0xFF00702F)],
  );

  /// Calm gradient for completed / neutral hero states.
  static const LinearGradient slateGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5A6A62), Color(0xFF39443E)],
  );

  /// Soft elevation for white cards — subtle, not heavy.
  static const List<BoxShadow> shadowCard = [
    BoxShadow(color: Color(0x0D101814), blurRadius: 14, offset: Offset(0, 6)),
  ];

  /// Colored glow for a gradient hero surface. Tint with the state colour.
  static List<BoxShadow> glow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.30),
      blurRadius: 22,
      offset: const Offset(0, 12),
    ),
  ];
}
