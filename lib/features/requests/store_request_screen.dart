import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/brand.dart';
import '../auth/auth_controller.dart';
import 'request_kit.dart';

class _ItemDraft {
  _ItemDraft()
    : itemDescription = TextEditingController(),
      quantity = TextEditingController(),
      location = TextEditingController(),
      remarks = TextEditingController();

  final TextEditingController itemDescription;
  final TextEditingController quantity;
  final TextEditingController location;
  final TextEditingController remarks;

  void dispose() {
    itemDescription.dispose();
    quantity.dispose();
    location.dispose();
    remarks.dispose();
  }
}

class StoreRequestItemView {
  const StoreRequestItemView({
    required this.itemDescription,
    required this.quantity,
    this.location = '',
    this.remarks = '',
  });
  final String itemDescription;
  final String quantity;
  final String location;
  final String remarks;

  factory StoreRequestItemView.fromJson(Map<String, dynamic> j) => StoreRequestItemView(
    itemDescription: j['item_description'] as String? ?? '',
    quantity: j['quantity'] as String? ?? '',
    location: j['location'] as String? ?? '',
    remarks: j['remarks'] as String? ?? '',
  );
}

/// One stage of the Request Note: verified / approved / issued.
class StoreStage {
  const StoreStage(this.decision, this.byName, this.note);
  final String decision;
  final String byName;
  final String note;

  factory StoreStage.fromJson(Map<String, dynamic> j, String key) => StoreStage(
    j['${key}_decision'] as String? ?? 'pending',
    j['${key}_by_name'] as String? ?? '',
    j['${key}_note'] as String? ?? '',
  );
}

class StoreRequestView {
  const StoreRequestView({
    required this.id,
    required this.status,
    required this.items,
    this.employeeId = '',
    this.fullName = '',
    this.department = '',
    this.descriptionOfWorks = '',
    this.verify = const StoreStage('pending', '', ''),
    this.hod = const StoreStage('pending', '', ''),
    this.issue = const StoreStage('pending', '', ''),
    this.canDecide,
  });
  final int id;
  final String status;
  final List<StoreRequestItemView> items;
  final String employeeId;
  final String fullName;
  final String department;
  final String descriptionOfWorks;
  final StoreStage verify;
  final StoreStage hod;
  final StoreStage issue;

  /// The step the signed-in user can take now, per the server:
  /// 'verify', 'hod-decision', 'issue' or null.
  final String? canDecide;

  String get reference => 'SR-${id.toString().padLeft(5, '0')}';
  String get itemSummary => items.map((i) => i.itemDescription).join(', ');

  factory StoreRequestView.fromJson(Map<String, dynamic> j) => StoreRequestView(
    id: j['id'] as int,
    status: j['status'] as String? ?? 'pending_verification',
    items: (j['items'] as List? ?? [])
        .map((e) => StoreRequestItemView.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    employeeId: j['employee_id'] as String? ?? '',
    fullName: j['full_name'] as String? ?? '',
    department: j['department'] as String? ?? '',
    descriptionOfWorks: j['description_of_works'] as String? ?? '',
    verify: StoreStage.fromJson(j, 'verify'),
    hod: StoreStage.fromJson(j, 'hod'),
    issue: StoreStage.fromJson(j, 'issue'),
    canDecide: j['can_decide'] as String?,
  );
}

class StoreRequestScreen extends ConsumerStatefulWidget {
  const StoreRequestScreen({super.key});

  @override
  ConsumerState<StoreRequestScreen> createState() => _StoreRequestScreenState();
}

class _StoreRequestScreenState extends ConsumerState<StoreRequestScreen> {
  bool _loadingList = true;
  List<StoreRequestView> _items = [];

  bool _formOpen = false;
  final _description = TextEditingController();
  final List<_ItemDraft> _rows = [_ItemDraft()];
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadingList = true);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/api/requisitions/store');
      final rows = (res.data['requests'] as List)
          .map((e) => StoreRequestView.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      setState(() => _items = rows);
    } on DioException {
      // Leave list empty on failure — RefreshIndicator lets them retry.
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _submit() async {
    final cleanItems = _rows
        .where((r) => r.itemDescription.text.trim().isNotEmpty)
        .map(
          (r) => {
            'item_description': r.itemDescription.text.trim(),
            'quantity': r.quantity.text.trim(),
            'location': r.location.text.trim(),
            'remarks': r.remarks.text.trim(),
          },
        )
        .toList();
    if (cleanItems.isEmpty) {
      setState(() => _error = 'Add at least one item.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(
        '/api/requisitions/store',
        data: {
          'description_of_works': _description.text.trim(),
          'items': cleanItems,
        },
      );
      setState(() {
        _formOpen = false;
        _description.clear();
        for (final r in _rows) {
          r.dispose();
        }
        _rows
          ..clear()
          ..add(_ItemDraft());
      });
      final sent = StoreRequestView.fromJson(Map<String, dynamic>.from(res.data));
      unawaited(_load());
      if (mounted) {
        await showSubmittedSheet(
          context,
          title: 'Store request ${sent.reference} submitted',
          subtitle: '${sent.items.length} item${sent.items.length == 1 ? '' : 's'} · '
              'sent to Stores to verify.',
          onShare: (btn) => _share(btn, sent),
        );
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      setState(() {
        _error = (data is Map && data['detail'] is String)
            ? data['detail'] as String
            : 'Could not submit your request.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      appBar: AppBar(
        title: const Text('Store requests'),
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
            if (_loadingList)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator(color: Brand.green)),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text('No store requests yet.', style: TextStyle(color: Brand.slate)),
                ),
              )
            else ...[
              if (_toDecide.isNotEmpty) ...[
                requestSectionLabel('Needs your action (${_toDecide.length})', Brand.orange),
                ..._toDecide.map(_buildRow),
                if (_others.isNotEmpty) requestSectionLabel('All requests', Brand.slate),
              ],
              ..._others.map(_buildRow),
            ],
          ],
        ),
      ),
    );
  }

  List<StoreRequestView> get _toDecide => _items.where((r) => r.canDecide != null).toList();
  List<StoreRequestView> get _others => _items.where((r) => r.canDecide == null).toList();

  Future<void> _share(BuildContext button, StoreRequestView r) => shareApiPdf(
        button,
        ref.read(dioProvider),
        url: '/api/requisitions/store/${r.id}/pdf',
        filename: 'store-request-${r.reference}.pdf',
        text: 'Store request ${r.reference}: ${r.itemSummary}',
        subject: 'Store request ${r.reference}',
      );

  void _openDetail(StoreRequestView r) => showRequestSheet(
        context,
        _StoreDetail(item: r, onChanged: _load, onShare: _share),
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
            'New store request',
            style: TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Detailed description of works to be done',
            ),
          ),
          const SizedBox(height: 14),
          const Text('Items', style: TextStyle(fontWeight: FontWeight.w600, color: Brand.ink)),
          const SizedBox(height: 8),
          for (var i = 0; i < _rows.length; i++) _buildItemRow(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _rows.add(_ItemDraft())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add item'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(color: Brand.red)),
          ],
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : const Text('Submit request'),
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
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: row.itemDescription,
                  decoration: const InputDecoration(labelText: 'Item'),
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
                  controller: row.quantity,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: row.location,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
              ),
            ],
          ),
          TextField(
            controller: row.remarks,
            decoration: const InputDecoration(labelText: 'Remarks (optional)'),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(StoreRequestView r) {
    final me = ref.read(authControllerProvider).user;
    final someoneElse = me != null && r.employeeId.isNotEmpty && r.employeeId != me.employeeId;
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
                      r.itemSummary,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                      r.items.map((i) => '${i.itemDescription} (${i.quantity})').join(' · '),
                      style: const TextStyle(color: Brand.slate, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

/// A store request in full, and — for whoever holds the next step — that step.
class _StoreDetail extends ConsumerWidget {
  const _StoreDetail({required this.item, required this.onChanged, required this.onShare});
  final StoreRequestView item;
  final Future<void> Function() onChanged;
  final Future<void> Function(BuildContext button, StoreRequestView r) onShare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = item;
    final dio = ref.read(dioProvider);
    final (title, approve, decline) = switch (r.canDecide) {
      'verify' => ('Verify (Stores)', 'Verify', 'Not in stock'),
      'issue' => ('Issue (Stores)', 'Mark issued', "Can't issue"),
      _ => ('Your decision (HOD)', 'Approve', 'Decline'),
    };

    Future<String?> decide(String decision, String note) async {
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      try {
        await dio.patch(
          '/api/requisitions/store/${r.id}/${r.canDecide}',
          data: {'decision': decision, 'note': note},
        );
        await onChanged();
        nav.pop();
        messenger.showSnackBar(SnackBar(
          content: Text(decision == 'rejected'
              ? '${r.reference} declined.'
              : switch (r.canDecide) {
                  'verify' => '${r.reference} verified.',
                  'issue' => '${r.reference} marked issued.',
                  _ => '${r.reference} approved — Stores can issue it.',
                }),
        ));
        return null;
      } catch (e) {
        return apiError(e, 'That wasn\'t saved.');
      }
    }

    return RequestSheet(
      children: [
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
        if (r.fullName.isNotEmpty)
          Text('${r.fullName} · ${r.department}', style: const TextStyle(color: Brand.slate, fontSize: 12)),
        if (r.descriptionOfWorks.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(r.descriptionOfWorks, style: const TextStyle(color: Brand.ink)),
        ],
        const SizedBox(height: 12),
        for (final i in r.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.itemDescription, style: const TextStyle(color: Brand.ink)),
                      if (i.location.isNotEmpty || i.remarks.isNotEmpty)
                        Text(
                          [i.location, i.remarks].where((s) => s.isNotEmpty).join(' · '),
                          style: const TextStyle(color: Brand.slate, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                Text(i.quantity, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        const Divider(),
        StageLine(who: 'Stores', decision: r.verify.decision, note: r.verify.note, by: r.verify.byName, approvedLabel: 'Verified'),
        StageLine(who: 'Head of Department', decision: r.hod.decision, note: r.hod.note, by: r.hod.byName),
        StageLine(who: 'Stores', decision: r.issue.decision, note: r.issue.note, by: r.issue.byName, approvedLabel: 'Issued'),
        if (r.canDecide != null)
          DecisionPanel(
            title: title,
            what: r.reference,
            approveLabel: approve,
            declineLabel: decline,
            onDecide: decide,
          ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => openApiFile(
            context,
            dio,
            '/api/requisitions/store/${r.id}/pdf',
            'store-request-${r.reference}.pdf',
          ),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Open form (PDF)'),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (btn) => OutlinedButton.icon(
            onPressed: () => onShare(btn, r),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share'),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'issued' => (Brand.green, 'Issued'),
      'rejected' => (Brand.red, 'Rejected'),
      'pending_hod' => (Brand.blue, 'Pending HOD'),
      'pending_issuance' => (Colors.purple, 'Pending Issuance'),
      _ => (Brand.orange, 'Pending Verification'),
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
