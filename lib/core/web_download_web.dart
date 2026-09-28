import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Hand bytes fetched with the user's token (a PDF form) to the browser as a
/// download. A plain link can't carry the Authorization header, so the app
/// fetches the file itself and then saves it from memory.
void saveBytesInBrowser(List<int> bytes, String filename, String mimeType) {
  final blob = web.Blob(
    [Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  // Give the browser time to start the download before freeing the blob.
  Future<void>.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}

/// Share a file through the browser's share sheet where it can share files
/// (phones, Safari, Edge); download it where it can't.
/// Returns 'shared', 'cancelled' or 'downloaded'.
Future<String> shareBytesInBrowser(
  List<int> bytes,
  String filename,
  String mimeType, {
  required String title,
  required String text,
}) async {
  final file = web.File(
    [Uint8List.fromList(bytes).toJS].toJS,
    filename,
    web.FilePropertyBag(type: mimeType),
  );
  final data = web.ShareData(files: [file].toJS, title: title, text: text);
  var canShare = false;
  try {
    canShare = web.window.navigator.canShare(data);
  } catch (_) {
    // Older browsers have no canShare at all.
  }
  if (canShare) {
    try {
      await web.window.navigator.share(data).toDart;
      return 'shared';
    } catch (e) {
      // The user closing the share sheet rejects with an AbortError. Checked
      // by name: a JS exception's Dart type differs between JS and Wasm.
      if (e.toString().contains('AbortError')) return 'cancelled';
      // Some browsers claim support and then refuse: fall through.
    }
  }
  saveBytesInBrowser(bytes, filename, mimeType);
  return 'downloaded';
}
