/// Non-web builds never call these; see web_download_web.dart.
void saveBytesInBrowser(List<int> bytes, String filename, String mimeType) {
  throw UnsupportedError('saveBytesInBrowser is web-only');
}

Future<String> shareBytesInBrowser(
  List<int> bytes,
  String filename,
  String mimeType, {
  required String title,
  required String text,
}) {
  throw UnsupportedError('shareBytesInBrowser is web-only');
}
