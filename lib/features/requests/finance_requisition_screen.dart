import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/brand.dart';
import '../auth/auth_controller.dart';
import 'request_kit.dart';

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
    this.approvedAmount,
    this.reductionReason = '',
    this.fullName = '',
    this.department = '',
    this.hodByName = '',
    this.financeByName = '',
    this.canDecide,
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
  /// What Finance authorised — may be less than [total]; null until approved.
  final double? approvedAmount;
  final String reductionReason;
  final String fullName;
  final String department;
  final String hodByName;
  final String financeByName;

  /// The decision the signed-in user can make now, as the server sees it:
  /// 'hod-decision', 'decision' (Finance) or null.
  final String? canDecide;

  bool get isReduced => approvedAmount != null && approvedAmount! < total;

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
        approvedAmount: approvedAmount,
        reductionReason: reductionReason,
        fullName: fullName,
        department: department,
        hodByName: hodByName,
        financeByName: financeByName,
        canDecide: canDecide,
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
      approvedAmount: (j['approved_amount'] as num?)?.toDouble(),
      reductionReason: j['reduction_reason'] as String? ?? '',
      fullName: j['full_name'] as String? ?? '',
      department: j['department'] as String? ?? '',
      hodByName: j['hod_by_name'] as String? ?? '',
      financeByName: j['finance_by_name'] as String? ?? '',
      canDecide: j['can_decide'] as String?,
    );
  }
}

String _dioMessage(Object e, String fallback) => apiError(e, fallback);

/// Share the filled-in form (with its documents) — WhatsApp, email, Drive on
/// a phone; the browser's share sheet or a download on the web.
Future<void> _shareRequisition(
  BuildContext context,
  Dio dio,
  FinanceRequisitionView r,
) =>
    shareApiPdf(
      context,
      dio,
      url: '/api/requisitions/finance/${r.id}/pdf',
      filename: 'requisition-${r.reference}.pdf',
      text: 'Finance requisition ${r.reference}: UGX ${_money(r.approvedAmount ?? r.total)}'
          '${r.itemSummary.isEmpty ? '' : ' — ${r.itemSummary}'}',
      subject: 'Requisition ${r.reference}',
    );

Future<void> _openRemote(BuildContext context, Dio dio, String url, String filename) =>
    openApiFile(context, dio, url, filename);

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
      final res = await dio.post(
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
      final sent = FinanceRequisitionView.fromJson(Map<String, dynamic>.from(res.data));
      unawaited(_load());
      if (mounted) await _showSubmitted(sent);
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

  /// Confirmation after submitting, with the form ready to share — a
  /// requester often has to forward it to someone the moment it's in.
  Future<void> _showSubmitted(FinanceRequisitionView r) {
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
                'Requisition ${r.reference} submitted',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: Brand.ink),
              ),
              const SizedBox(height: 4),
              Text(
                'UGX ${_money(r.total)} · sent to your HOD for approval.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Brand.slate),
              ),
              const SizedBox(height: 18),
              Builder(
                builder: (btn) => FilledButton.icon(
                  onPressed: () => _shareRequisition(btn, ref.read(dioProvider), r),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share form (PDF)'),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(sheet).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
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
            else ...[
              if (_toDecide.isNotEmpty) ...[
                _sectionLabel('Needs your decision (${_toDecide.length})', Brand.orange),
                ..._toDecide.map(_buildRow),
                if (_others.isNotEmpty) _sectionLabel('All requisitions', Brand.slate),
              ],
              ..._others.map(_buildRow),
            ],
          ],
        ),
      ),
    );
  }

  List<FinanceRequisitionView> get _toDecide =>
      _items.where((r) => r.canDecide != null).toList();
  List<FinanceRequisitionView> get _others =>
      _items.where((r) => r.canDecide == null).toList();

  Widget _sectionLabel(String text, Color color) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          text,
          style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 13),
        ),
      );

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
    final me = ref.read(authControllerProvider).user;
    final someoneElse = me != null && r.employeeId != me.employeeId;
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
                      'UGX ${_money(r.approvedAmount ?? r.total)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
                    ),
                    if (r.isReduced)
                      Text(
                        'Reduced from ${_money(r.total)}',
                        style: const TextStyle(color: Brand.slate, fontSize: 11),
                      ),
                    if (someoneElse)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${r.fullName} · ${r.department}',
                          style: const TextStyle(color: Brand.ink, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
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
              if (r.canDecide != null)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('Review', style: TextStyle(color: Brand.orange, fontWeight: FontWeight.w700, fontSize: 12)),
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

  // Decision panel. Only the Finance stage can approve a reduced amount.
  final _note = TextEditingController();
  late final _amount = TextEditingController(
    text: widget.requisition.total % 1 == 0
        ? _money(widget.requisition.total)
        : widget.requisition.total.toStringAsFixed(2),
  );
  final _reason = TextEditingController();
  String? _decisionError;
  String? _deciding; // 'approved' | 'rejected' while a decision is saving

  @override
  void dispose() {
    _note.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _financeStage => r.canDecide == 'decision';
  double get _approving => _amount.text.trim().isEmpty ? r.total : (_num(_amount.text) ?? -1);
  double get _cut => _financeStage ? r.total - _approving : 0;

  String? get _amountProblem {
    if (!_financeStage) return null;
    final a = _approving;
    if (a <= 0) return 'Enter an amount above zero — or decline it.';
    if (a > r.total) return "Can't be more than the UGX ${_money(r.total)} requested.";
    return null;
  }

  Future<void> _decide(String decision) async {
    final approving = decision == 'approved';
    if (approving && _amountProblem != null) {
      setState(() => _decisionError = _amountProblem);
      return;
    }
    if (approving && _cut > 0 && _reason.text.trim().isEmpty) {
      setState(() => _decisionError = 'Say why the amount was reduced — the requester and their HOD see it.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    if (!approving) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Decline ${r.reference}?'),
          content: Text(
            _note.text.trim().isEmpty
                ? 'The requester will be told. Consider adding remarks so they know why.'
                : 'The requester will be told, with your remarks.',
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
      if (ok != true || !mounted) return;
    }
    setState(() {
      _deciding = decision;
      _decisionError = null;
    });
    try {
      final out = await ref.read(dioProvider).patch(
        '/api/requisitions/finance/${r.id}/${r.canDecide}',
        data: {
          'decision': decision,
          'note': _note.text.trim(),
          if (_financeStage && approving) 'approved_amount': _approving,
          if (_financeStage && approving && _cut > 0) 'reduction_reason': _reason.text.trim(),
        },
      );
      final updated = FinanceRequisitionView.fromJson(Map<String, dynamic>.from(out.data));
      await widget.onChanged();
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(switch ((decision, updated.status)) {
          ('rejected', _) => '${r.reference} declined.',
          (_, 'pending_finance') => '${r.reference} approved — sent to Finance.',
          _ when updated.isReduced =>
            '${r.reference} approved at UGX ${_money(updated.approvedAmount!)}.',
          _ => '${r.reference} approved.',
        }),
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _decisionError = _dioMessage(e, 'That decision wasn\'t saved.'));
      }
    } finally {
      if (mounted) setState(() => _deciding = null);
    }
  }

  Widget _decisionPanel() {
    final problem = _amountProblem;
    final cut = _cut;
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
          Text(
            _financeStage ? 'Your decision (Finance)' : 'Your decision (HOD)',
            style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
          ),
          const SizedBox(height: 10),
          if (_financeStage) ...[
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _decisionError = null),
              decoration: InputDecoration(
                labelText: 'Amount to approve',
                prefixText: 'UGX ',
                filled: true,
                fillColor: Colors.white,
                errorText: problem,
                helperText: problem != null
                    ? null
                    : cut > 0
                        ? 'Reduced by UGX ${_money(cut)} from ${_money(r.total)} requested'
                        : 'The full amount requested. Lower it to approve less.',
              ),
            ),
            if (cut > 0 && problem == null) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 4,
                onChanged: (_) => setState(() => _decisionError = null),
                decoration: const InputDecoration(
                  labelText: 'Reason for the reduction (required)',
                  hintText: 'e.g. Budget allows only 3 tyres this quarter',
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Remarks (optional — the requester sees this)',
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          if (_decisionError != null) ...[
            const SizedBox(height: 8),
            Text(_decisionError!, style: const TextStyle(color: Brand.red)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _deciding != null ? null : () => _decide('rejected'),
                  style: OutlinedButton.styleFrom(foregroundColor: Brand.red),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(_deciding == 'rejected' ? 'Declining…' : 'Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _deciding != null ? null : () => _decide('approved'),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(
                    _deciding == 'approved'
                        ? 'Approving…'
                        : cut > 0 && problem == null
                            ? 'Approve ${_money(_approving)}'
                            : 'Approve',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
        // Lift the decision fields above the keyboard.
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
              '${r.fullName.isEmpty ? '' : '${r.fullName} · ${r.department} · '}'
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
          if (r.isReduced)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                border: Border.all(color: const Color(0xFFF5C26B)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Finance approved UGX ${_money(r.approvedAmount!)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
                  ),
                  Text(
                    'of UGX ${_money(r.total)} requested (−${_money(r.total - r.approvedAmount!)})',
                    style: const TextStyle(color: Brand.slate, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text('Reason: ${r.reductionReason}', style: const TextStyle(color: Brand.ink)),
                ],
              ),
            ),
          const SizedBox(height: 18),
          _stage('Head of Department', r.hodDecision, r.hodNote, r.hodByName),
          _stage('Finance', r.financeDecision, r.financeNote, r.financeByName),
          if (r.canDecide != null) _decisionPanel(),
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
          const SizedBox(height: 8),
          Builder(
            builder: (btn) => OutlinedButton.icon(
              onPressed: () => _shareRequisition(btn, dio, r),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stage(String who, String decision, String note, String by) {
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
