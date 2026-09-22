/// Build-time configuration injected via --dart-define.
///
/// Default backendUrl is the live Railway deployment. Override for local dev:
///   - Same-WiFi LAN (dev PC IP): --dart-define=BACKEND_URL=http://192.168.1.176:8000
///   - Android emulator:          --dart-define=BACKEND_URL=http://10.0.2.2:8000
///   - adb reverse tunnel / USB:  --dart-define=BACKEND_URL=http://localhost:8000
class Config {
  static const String backendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://web-production-2496d.up.railway.app',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '165605340230-3bvm248mk3bhlcf3ribccgdg69rmdkbs.apps.googleusercontent.com',
  );

  /// Web-only: the browser-facing OAuth client (origin-restricted, distinct
  /// from the server/mobile client above — see backend
  /// GOOGLE_OAUTH_WEB_CLIENT_ID). Must have this build's serving origin
  /// registered under "Authorized JavaScript origins" in Google Cloud
  /// Console, or sign-in fails with an origin-mismatch error.
  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '165605340230-rvbdvcnsdveelikseiua263li34djqei.apps.googleusercontent.com',
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
