import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/brand.dart';
import '../../core/web_download_stub.dart'
    if (dart.library.js_interop) '../../core/web_download_web.dart';

/// Pieces shared by the leave, store and finance screens: fetching the
/// printable form, sharing it, and the approve/decline controls an approver
/// sees. The server decides who may act (each row's `can_decide`); these
/// only render what it allows.

String apiError(Object e, String fallback) {
  if (e is DioException) {
    if (e.response == null) return 'No connection. Try again when you have signal.';
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
  }
  return fallback;
}

Future<File> downloadApiFile(Dio dio, String url, String filename) async {
  final res = await dio.get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
  );
  final dir = await getTemporaryDirectory();
  final safe = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(res.data ?? const []);
  return file;
}

Future<List<int>> fetchApiBytes(Dio dio, String url) async {
  final res = await dio.get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
  );
  return res.data ?? const [];
}

String _mimeFor(String filename) => switch (filename.split('.').last.toLowerCase()) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'csv' => 'text/csv',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => 'application/octet-stream',
    };

/// Open a file from the API: in whatever viewer the phone has, or — on the
/// web — saved through the browser.
Future<void> openApiFile(BuildContext context, Dio dio, String url, String filename) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Text(kIsWeb ? 'Downloading $filename…' : 'Opening $filename…'),
      duration: const Duration(seconds: 2),
    ),
  );
  if (kIsWeb) {
    try {
      saveBytesInBrowser(await fetchApiBytes(dio, url), filename, _mimeFor(filename));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiError(e, 'Could not download $filename.'))));
    }
    return;
  }
  try {
    final file = await downloadApiFile(dio, url, filename);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      messenger.showSnackBar(SnackBar(content: Text('No app on this phone can open $filename.')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(apiError(e, 'Could not open $filename.'))));
  }
}

/// Hand a form from the API to the phone's share sheet (WhatsApp, email,
/// Drive…). `context` should be the button's, so iPad can anchor the popover.
Future<void> shareApiPdf(
  BuildContext context,
  Dio dio, {
  required String url,
  required String filename,
  required String text,
  required String subject,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  messenger.showSnackBar(
    const SnackBar(content: Text('Preparing the form…'), duration: Duration(seconds: 2)),
  );
  try {
    if (kIsWeb) {
      final how = await shareBytesInBrowser(
        await fetchApiBytes(dio, url),
        filename,
        'application/pdf',
        title: subject,
        text: text,
      );
      if (how == 'downloaded') {
        messenger.showSnackBar(const SnackBar(
          content: Text("This browser can't share files, so the PDF was downloaded — attach it to an email or chat."),
        ));
      }
      return;
    }
    final file = await downloadApiFile(dio, url, filename);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      text: text,
      subject: subject,
      sharePositionOrigin: origin,
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(apiError(e, 'Could not share the form.'))));
  }
}

/// "Submitted" confirmation with the form ready to share.
Future<void> showSubmittedSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Future<void> Function(BuildContext button) onShare,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle, color: Brand.green, size: 44),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Brand.ink),
            ),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Brand.slate)),
            const SizedBox(height: 18),
            Builder(
              builder: (btn) => FilledButton.icon(
                onPressed: () => onShare(btn),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share form (PDF)'),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: () => Navigator.of(sheet).pop(), child: const Text('Done')),
          ],
        ),
      ),
    ),
  );
}

Future<bool> confirmDecline(BuildContext context, String what, {required bool hasRemarks}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text('Decline $what?'),
      content: Text(
        hasRemarks
            ? 'The requester will be told, with your remarks.'
            : 'The requester will be told. Consider adding remarks so they know why.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Brand.red),
          onPressed: () => Navigator.pop(d, true),
          child: const Text('Decline'),
        ),
      ],
    ),
  );
  return ok == true;
}

Widget requestSectionLabel(String text, Color color) => Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13)),
    );

/// One stage of the chain: who it's for, what they decided, who, and why.
class StageLine extends StatelessWidget {
  const StageLine({
    super.key,
    required this.who,
    required this.decision,
    this.note = '',
    this.by = '',
    this.approvedLabel = 'Approved',
  });
  final String who;
  final String decision;
  final String note;
  final String by;
  final String approvedLabel;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (decision) {
      'approved' => (Icons.check_circle, Brand.green, approvedLabel),
      'rejected' => (Icons.cancel, Brand.red, 'Declined'),
      _ => (Icons.schedule, Brand.mute, 'Waiting'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$who · $label', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (by.isNotEmpty && decision != 'pending')
                  Text(by, style: const TextStyle(color: Brand.slate, fontSize: 12)),
                if (note.isNotEmpty)
                  Text('“$note”', style: const TextStyle(color: Brand.slate, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The approver's box: stage-specific fields on top, remarks, then
/// Decline / Approve. `onDecide` does the request and returns an error
/// message, or null on success.
class DecisionPanel extends StatefulWidget {
  const DecisionPanel({
    super.key,
    required this.title,
    required this.onDecide,
    this.fields = const [],
    this.approveLabel = 'Approve',
    this.declineLabel = 'Decline',
    this.remarksHint,
    required this.what,
  });

  final String title;
  final String what; // "LV-00012", for the decline confirmation
  final List<Widget> fields;
  final String approveLabel;
  final String declineLabel;
  final String? remarksHint;
  final Future<String?> Function(String decision, String note) onDecide;

  @override
  State<DecisionPanel> createState() => _DecisionPanelState();
}

class _DecisionPanelState extends State<DecisionPanel> {
  final _note = TextEditingController();
  String? _busy;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _go(String decision) async {
    if (decision == 'rejected' &&
        !await confirmDecline(context, widget.what, hasRemarks: _note.text.trim().isNotEmpty)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = decision;
      _error = null;
    });
    final err = await widget.onDecide(decision, _note.text.trim());
    if (mounted) {
      setState(() {
        _busy = null;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink)),
          const SizedBox(height: 10),
          for (final f in widget.fields) ...[f, const SizedBox(height: 10)],
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Remarks (optional — the requester sees this)',
              hintText: widget.remarksHint,
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Brand.red)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy != null ? null : () => _go('rejected'),
                  style: OutlinedButton.styleFrom(foregroundColor: Brand.red),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(_busy == 'rejected' ? 'Declining…' : widget.declineLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy != null ? null : () => _go('approved'),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(_busy == 'approved' ? 'Saving…' : widget.approveLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet frame used by every request's detail view: drag handle,
/// keyboard-aware padding, scrollable.
class RequestSheet extends StatelessWidget {
  const RequestSheet({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + MediaQuery.viewInsetsOf(context).bottom),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Brand.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

Future<void> showRequestSheet(BuildContext context, Widget child) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => child,
    );
