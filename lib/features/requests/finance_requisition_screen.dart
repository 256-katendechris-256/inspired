import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/api_client.dart';
import '../../core/brand.dart';
import '../auth/auth_controller.dart';

// Mirrors apps/requisitions/attachments.py — the server enforces the same
// limits; checking here just saves uploading a file that will be refused.
const _maxFiles = 5;
const _maxBytes = 10 * 1024 * 1024;
const _allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'docx', 'xlsx', 'csv'];

String _money(num v) {
  final s = v.round().abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}$out';
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

double? _num(String raw) => double.tryParse(raw.replaceAll(',', '').trim());

IconData _iconFor(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return switch (ext) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'jpg' || 'jpeg' || 'png' || 'webp' => Icons.image_outlined,
    'xlsx' || 'csv' => Icons.table_chart_outlined,
    'docx' => Icons.description_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

class _ItemDraft {
  _ItemDraft()
    : particulars = TextEditingController(),
      qty = TextEditingController(),
      unitCost = TextEditingController();

  final TextEditingController particulars;
  final TextEditingController qty;
  final TextEditingController unitCost;

  double get lineTotal => (_num(qty.text) ?? 0) * (_num(unitCost.text) ?? 0);

  void dispose() {
    particulars.dispose();
    qty.dispose();
    unitCost.dispose();
  }
}

/// A document chosen on the phone, not yet uploaded.
class _PickedDoc {
  const _PickedDoc({required this.name, required this.size, this.path, this.bytes});
  final String name;
  final int size;
  final String? path;
  final List<int>? bytes; // web has no file paths

  Future<MultipartFile> toMultipart() => path != null
      ? MultipartFile.fromFile(path!, filename: name)
      : Future.value(MultipartFile.fromBytes(bytes!, filename: name));
}

class FinanceAttachment {
  const FinanceAttachment({
    required this.id,
    required this.filename,
    required this.size,
    required this.url,
  });
  final int id;
  final String filename;
  final int size;
  final String url;

  factory FinanceAttachment.fromJson(Map<String, dynamic> j) => FinanceAttachment(
    id: j['id'] as int,
    filename: j['filename'] as String? ?? 'document',
    size: (j['size'] as num?)?.toInt() ?? 0,
    url: j['url'] as String? ?? '',
  );
}

class FinanceLine {
  const FinanceLine(this.particulars, this.qty, this.unitCost, this.amount);
  final String particulars;
  final double qty;
  final double unitCost;
  final double amount;
}

class FinanceRequisitionView {
  const FinanceRequisitionView({
    required this.id,
    required this.employeeId,
    required this.status,
    required this.total,
    required this.amountInWords,
    required this.lines,
    required this.attachments,
    required this.createdAt,
    this.hodDecision = 'pending',
    this.hodNote = '',
    this.financeDecision = 'pending',
    this.financeNote = '',
  });
  final int id;
  final String employeeId;
  final String status;
  final double total;
  final String amountInWords;
  final List<FinanceLine> lines;
  final List<FinanceAttachment> attachments;
  final DateTime? createdAt;
  final String hodDecision;
  final String hodNote;
  final String financeDecision;
  final String financeNote;

  String get reference => 'FR-${id.toString().padLeft(5, '0')}';

  FinanceRequisitionView copyWith({List<FinanceAttachment>? attachments}) =>
      FinanceRequisitionView(
        id: id,
        employeeId: employeeId,
        status: status,
        total: total,
        amountInWords: amountInWords,
        lines: lines,
        attachments: attachments ?? this.attachments,
        createdAt: createdAt,
        hodDecision: hodDecision,
        hodNote: hodNote,
        financeDecision: financeDecision,
        financeNote: financeNote,
      );

  String get itemSummary =>
      lines.map((l) => l.particulars).where((s) => s.isNotEmpty).join(', ');

  factory FinanceRequisitionView.fromJson(Map<String, dynamic> j) {
    double d(Object? v) => (v as num?)?.toDouble() ?? 0;
    return FinanceRequisitionView(
      id: j['id'] as int,
      employeeId: j['employee_id'] as String? ?? '',
      status: j['status'] as String? ?? 'pending_hod',
      total: d(j['total']),
      amountInWords: j['amount_in_words'] as String? ?? '',
      lines: (j['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((e) => FinanceLine(
                e['particulars'] as String? ?? '',
                d(e['qty']),
                d(e['unit_cost']),
                d(e['amount']),
              ))
          .toList(),
      attachments: (j['attachments'] as List? ?? [])
          .map((e) => FinanceAttachment.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal(),
      hodDecision: j['hod_decision'] as String? ?? 'pending',
      hodNote: j['hod_note'] as String? ?? '',
      financeDecision: j['finance_decision'] as String? ?? 'pending',
      financeNote: j['finance_note'] as String? ?? '',
    );
  }
}

String _dioMessage(Object e, String fallback) {
  if (e is DioException) {
    if (e.response == null) return 'No connection. Try again when you have signal.';
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
  }
  return fallback;
}

/// Download a file from the API into the temp folder and hand it to
/// whatever app on the phone opens that type (PDF viewer, gallery, Excel).
Future<void> _openRemote(
  BuildContext context,
  Dio dio,
  String url,
  String filename,
) async {
  final messenger = ScaffoldMessenger.of(context);
  if (kIsWeb) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Open this from the dashboard on the web.')),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(content: Text('Opening $filename…'), duration: const Duration(seconds: 2)),
  );
  try {
    final res = await dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final dir = await getTemporaryDirectory();
    final safe = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File('${dir.path}/$safe');
    await file.writeAsBytes(res.data ?? const []);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      messenger.showSnackBar(
        SnackBar(content: Text('No app on this phone can open $filename.')),
      );
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(_dioMessage(e, 'Could not open $filename.'))),
    );
  }
}

class FinanceRequisitionScreen extends ConsumerStatefulWidget {
  const FinanceRequisitionScreen({super.key});

  @override
  ConsumerState<FinanceRequisitionScreen> createState() =>
      _FinanceRequisitionScreenState();
}

class _FinanceRequisitionScreenState
    extends ConsumerState<FinanceRequisitionScreen> {
  bool _loadingList = true;
  List<FinanceRequisitionView> _items = [];

  bool _formOpen = false;
  final List<_ItemDraft> _rows = [_ItemDraft()];
  final List<_PickedDoc> _docs = [];
  bool _submitting = false;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadingList = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/api/requisitions/finance');
      final rows = (res.data['requisitions'] as List)
          .map((e) => FinanceRequisitionView.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (mounted) setState(() => _items = rows);
    } on DioException {
      // Leave list as-is on failure — RefreshIndicator lets them retry.
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  double get _draftTotal => _rows.fold(0, (sum, r) => sum + r.lineTotal);

  // --- documents ------------------------------------------------------------

  /// Adds what fits and explains what didn't, rather than all-or-nothing.
  void _addDocs(Iterable<_PickedDoc> picked) {
    final refused = <String>[];
    for (final d in picked) {
      final ext = d.name.split('.').last.toLowerCase();
      if (_docs.length >= _maxFiles) {
        refused.add('${d.name}: at most $_maxFiles documents');
      } else if (!_allowedExtensions.contains(ext)) {
        refused.add('${d.name}: attach PDF, photo, Word (.docx) or Excel (.xlsx)');
      } else if (d.size > _maxBytes) {
        refused.add('${d.name}: larger than 10 MB');
      } else {
        _docs.add(d);
      }
    }
    setState(() => _error = refused.isEmpty ? null : refused.join('\n'));
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: kIsWeb,
    );
    if (res == null) return;
    _addDocs(res.files.map(
      (f) => _PickedDoc(name: f.name, size: f.size, path: kIsWeb ? null : f.path, bytes: f.bytes),
    ));
  }

  Future<void> _takePhoto() async {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
      maxWidth: 2200,
      maxHeight: 2200,
    );
    if (shot == null) return;
    final stamp = DateTime.now();
    final name = 'receipt-${stamp.year}${stamp.month.toString().padLeft(2, '0')}'
        '${stamp.day.toString().padLeft(2, '0')}-${stamp.millisecondsSinceEpoch % 100000}.jpg';
    _addDocs([
      _PickedDoc(
        name: name,
        size: await shot.length(),
        path: kIsWeb ? null : shot.path,
        bytes: kIsWeb ? await shot.readAsBytes() : null,
      ),
    ]);
  }

  // --- submit ---------------------------------------------------------------

  Future<void> _submit() async {
    final cleanItems = <Map<String, String>>[];
    for (final (i, r) in _rows.indexed) {
      final name = r.particulars.text.trim();
      if (name.isEmpty) continue;
      final qty = _num(r.qty.text), cost = _num(r.unitCost.text);
      if (qty == null || qty <= 0 || cost == null || cost <= 0) {
        setState(() => _error = 'Line ${i + 1} ($name): enter a quantity and unit cost above zero.');
        return;
      }
      cleanItems.add({
        'particulars': name,
        'qty': r.qty.text.replaceAll(',', '').trim(),
        'unit_cost': r.unitCost.text.replaceAll(',', '').trim(),
      });
    }
    if (cleanItems.isEmpty) {
      setState(() => _error = 'Add at least one item.');
      return;
    }
    setState(() {
      _submitting = true;
      _progress = null;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final Object body;
      if (_docs.isEmpty) {
        body = {'items': cleanItems};
      } else {
        body = FormData.fromMap({
          'items': jsonEncode(cleanItems),
          'files': [for (final d in _docs) await d.toMultipart()],
        });
      }
      await dio.post(
        '/api/requisitions/finance',
        data: body,
        // Documents on a weak signal take a while; don't give up at 15s.
        options: _docs.isEmpty
            ? null
            : Options(sendTimeout: const Duration(minutes: 3), receiveTimeout: const Duration(minutes: 1)),
        onSendProgress: _docs.isEmpty
            ? null
            : (sent, total) {
                if (total > 0 && mounted) setState(() => _progress = sent / total);
              },
      );
      setState(() {
        _formOpen = false;
        for (final r in _rows) {
          r.dispose();
        }
        _rows
          ..clear()
          ..add(_ItemDraft());
        _docs.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Requisition sent to your HOD.')),
        );
      }
      await _load();
    } catch (e) {
      setState(() => _error = _dioMessage(e, 'Could not submit your requisition.'));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _progress = null;
        });
      }
    }
  }

  void _openDetail(FinanceRequisitionView r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _RequisitionDetail(requisition: r, onChanged: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      appBar: AppBar(
        title: const Text('Finance requisitions'),
        actions: [
          IconButton(
            icon: Icon(_formOpen ? Icons.close : Icons.add),
            onPressed: () => setState(() => _formOpen = !_formOpen),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: Brand.green,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_formOpen) _buildForm(),
            if (_formOpen) const SizedBox(height: 20),
            if (_loadingList && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator(color: Brand.green)),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text('No requisitions yet.', style: TextStyle(color: Brand.slate)),
                ),
              )
            else
              ..._items.map(_buildRow),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: Brand.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'New requisition',
            style: TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _rows.length; i++) _buildItemRow(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _rows.add(_ItemDraft())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add item'),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Total: UGX ${_money(_draftTotal)}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
            ),
          ),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'The amount in words is written on the form for you.',
              style: TextStyle(color: Brand.mute, fontSize: 11),
            ),
          ),
          const SizedBox(height: 16),
          _buildDocsSection(),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Brand.red)),
          ],
          const SizedBox(height: 12),
          if (_submitting && _progress != null) ...[
            LinearProgressIndicator(value: _progress, color: Brand.green),
            const SizedBox(height: 4),
            Text(
              'Uploading documents… ${((_progress ?? 0) * 100).round()}%',
              style: const TextStyle(color: Brand.slate, fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : const Text('Submit requisition'),
          ),
        ],
      ),
    );
  }

  Widget _buildDocsSection() {
    final full = _docs.length >= _maxFiles;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Supporting documents (optional)',
            style: TextStyle(fontWeight: FontWeight.w600, color: Brand.ink),
          ),
          const SizedBox(height: 2),
          const Text(
            'Quotations, invoices, receipts or budgets — photos, PDF, Word or Excel. '
            'They are printed behind your requisition form.',
            style: TextStyle(color: Brand.slate, fontSize: 12),
          ),
          const SizedBox(height: 8),
          for (final (i, d) in _docs.indexed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_iconFor(d.name), color: Brand.blue),
              title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_size(d.size)),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18, color: Brand.slate),
                tooltip: 'Remove',
                onPressed: _submitting ? null : () => setState(() => _docs.removeAt(i)),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: full || _submitting ? null : _pickFiles,
                icon: const Icon(Icons.attach_file, size: 18),
                label: const Text('Attach files'),
              ),
              if (!kIsWeb)
                OutlinedButton.icon(
                  onPressed: full || _submitting ? null : _takePhoto,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Take photo'),
                ),
            ],
          ),
          if (_docs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_docs.length} of $_maxFiles · up to 10 MB each',
                style: const TextStyle(color: Brand.mute, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItemRow(int i) {
    final row = _rows[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.circular(12),
      ),
      child: StatefulBuilder(
        builder: (context, setRowState) {
          void refresh() {
            setRowState(() {});
            setState(() {}); // the form total
          }

          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: row.particulars,
                      decoration: const InputDecoration(labelText: 'Particulars'),
                    ),
                  ),
                  if (_rows.length > 1)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: Brand.slate),
                      onPressed: () => setState(() {
                        _rows.removeAt(i).dispose();
                      }),
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: row.qty,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => refresh(),
                      decoration: const InputDecoration(labelText: 'Qty'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: row.unitCost,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => refresh(),
                      decoration: const InputDecoration(labelText: 'Unit cost (UGX)'),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _money(row.lineTotal),
                  style: const TextStyle(color: Brand.slate, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRow(FinanceRequisitionView r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: Brand.shadowCard,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(r),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UGX ${_money(r.total)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      r.itemSummary,
                      style: const TextStyle(color: Brand.slate, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (r.attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            const Icon(Icons.attach_file, size: 13, color: Brand.mute),
                            Text(
                              '${r.attachments.length} document${r.attachments.length == 1 ? '' : 's'}',
                              style: const TextStyle(color: Brand.mute, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              _StatusChip(status: r.status),
            ],
          ),
        ),
      ),
    );
  }
}

/// Everything about one requisition: what was asked, who has decided what
/// (with their remarks), the documents, and the printable form.
class _RequisitionDetail extends ConsumerStatefulWidget {
  const _RequisitionDetail({required this.requisition, required this.onChanged});
  final FinanceRequisitionView requisition;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_RequisitionDetail> createState() => _RequisitionDetailState();
}

class _RequisitionDetailState extends ConsumerState<_RequisitionDetail> {
  late FinanceRequisitionView r = widget.requisition;
  bool _busy = false;

  bool get _canEditDocs {
    final me = ref.read(authControllerProvider).user;
    return r.status == 'pending_hod' && me != null && me.employeeId == r.employeeId;
  }

  Future<void> _addDocs() async {
    final room = _maxFiles - r.attachments.length;
    final res = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: kIsWeb,
    );
    if (res == null || res.files.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final files = res.files.take(room).toList();
    if (files.any((f) => f.size > _maxBytes)) {
      messenger.showSnackBar(const SnackBar(content: Text('Each document must be 10 MB or less.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final form = FormData.fromMap({
        'files': [
          for (final f in files)
            kIsWeb
                ? MultipartFile.fromBytes(f.bytes!, filename: f.name)
                : await MultipartFile.fromFile(f.path!, filename: f.name),
        ],
      });
      final out = await ref.read(dioProvider).post(
        '/api/requisitions/finance/${r.id}/attachments',
        data: form,
        options: Options(sendTimeout: const Duration(minutes: 3)),
      );
      setState(() => r = FinanceRequisitionView.fromJson(Map<String, dynamic>.from(out.data)));
      await widget.onChanged();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_dioMessage(e, 'Could not attach the documents.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(FinanceAttachment a) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).delete(a.url);
      setState(() => r = r.copyWith(
            attachments: r.attachments.where((x) => x.id != a.id).toList(),
          ));
      await widget.onChanged();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_dioMessage(e, 'Could not remove it.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dio = ref.read(dioProvider);
    final created = r.createdAt;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Brand.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  r.reference,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Brand.ink),
                ),
              ),
              _StatusChip(status: r.status),
            ],
          ),
          if (created != null)
            Text(
              'Submitted ${created.day}/${created.month}/${created.year}',
              style: const TextStyle(color: Brand.slate, fontSize: 12),
            ),
          const SizedBox(height: 14),
          for (final l in r.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(l.particulars, style: const TextStyle(color: Brand.ink))),
                  Text(
                    '${l.qty % 1 == 0 ? l.qty.toInt() : l.qty} × ${_money(l.unitCost)}',
                    style: const TextStyle(color: Brand.slate, fontSize: 12),
                  ),
                  const SizedBox(width: 10),
                  Text(_money(l.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          const Divider(),
          Row(
            children: [
              const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w700))),
              Text('UGX ${_money(r.total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          if (r.amountInWords.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(r.amountInWords, style: const TextStyle(color: Brand.slate, fontSize: 12)),
            ),
          const SizedBox(height: 18),
          _stage('Head of Department', r.hodDecision, r.hodNote),
          _stage('Finance', r.financeDecision, r.financeNote),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text('Documents', style: TextStyle(fontWeight: FontWeight.w700, color: Brand.ink)),
              ),
              if (_canEditDocs && r.attachments.length < _maxFiles)
                TextButton.icon(
                  onPressed: _busy ? null : _addDocs,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
            ],
          ),
          if (r.attachments.isEmpty)
            const Text('None attached.', style: TextStyle(color: Brand.mute, fontSize: 12)),
          for (final a in r.attachments)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_iconFor(a.filename), color: Brand.blue),
              title: Text(a.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(_size(a.size)),
              onTap: () => _openRemote(context, dio, a.url, a.filename),
              trailing: _canEditDocs
                  ? IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Brand.slate),
                      tooltip: 'Remove',
                      onPressed: _busy ? null : () => _remove(a),
                    )
                  : null,
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => _openRemote(
              context,
              dio,
              '/api/requisitions/finance/${r.id}/pdf',
              'requisition-${r.reference}.pdf',
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(
              r.attachments.isEmpty ? 'Open form (PDF)' : 'Open form with documents (PDF)',
            ),
          ),
        ],
      ),
    );
  }

  Widget _stage(String who, String decision, String note) {
    final (icon, color, label) = switch (decision) {
      'approved' => (Icons.check_circle, Brand.green, 'Approved'),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'approved' => (Brand.green, 'Approved'),
      'rejected' => (Brand.red, 'Rejected'),
      'pending_finance' => (Brand.blue, 'Pending Finance'),
      _ => (Brand.orange, 'Pending HOD'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }
}
