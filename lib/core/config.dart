/// Build-time configuration injected via --dart-define.
///
/// Default backendUrl is the dev PC's LAN IP — verified reachable directly from
/// the physical phone, so it needs no fragile `adb reverse` tunnel. Override if
/// the PC's IP changes or you switch targets:
///   - Android emulator:          --dart-define=BACKEND_URL=http://10.0.2.2:8000
///   - adb reverse tunnel / USB:  --dart-define=BACKEND_URL=http://localhost:8000
class Config {
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://192.168.1.176:8000',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '',
  );

  /// Mapbox public token (pk.) — safe to embed in the client. Override with
  /// --dart-define=MAPBOX_TOKEN=... for production / a URL-restricted token.
  static const String mapboxToken = String.fromEnvironment(
    'MAPBOX_TOKEN',
    defaultValue: 'pk.eyJ1Ijoia2F0ZW5kZTA1Njg5IiwiYSI6ImNtcXFhbnZjbDBmNzUycXNsOWVjb3lnNHYifQ.J0su_Vt5LOAj2Dm6LEvA-g',
  );

  /// Mapbox style id. Try 'light-v11', 'streets-v12', or 'light-v11'.
  static const String mapboxStyle = String.fromEnvironment(
    'MAPBOX_STYLE',
    defaultValue: 'satellite-streets-v12',
  );

  static bool get hasMapbox => mapboxToken.isNotEmpty;
}
