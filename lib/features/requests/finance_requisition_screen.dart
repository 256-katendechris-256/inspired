import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/brand.dart';

class _ItemDraft {
  _ItemDraft()
    : particulars = TextEditingController(),
      qty = TextEditingController(),
      unitCost = TextEditingController();

  final TextEditingController particulars;
  final TextEditingController qty;
  final TextEditingController unitCost;

  double get lineTotal =>
      (double.tryParse(qty.text) ?? 0) * (double.tryParse(unitCost.text) ?? 0);

  void dispose() {
    particulars.dispose();
    qty.dispose();
    unitCost.dispose();
  }
}

class FinanceRequisitionView {
  const FinanceRequisitionView({
    required this.id,
    required this.status,
    required this.total,
    required this.itemSummary,
  });
  final int id;
  final String status;
  final double total;
  final String itemSummary;

  factory FinanceRequisitionView.fromJson(Map<String, dynamic> j) {
    final items = (j['items'] as List? ?? []);
    return FinanceRequisitionView(
      id: j['id'] as int,
      status: j['status'] as String? ?? 'pending_hod',
      total: (j['total'] as num?)?.toDouble() ?? 0,
      itemSummary: items
          .map((e) => (e as Map)['particulars'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .join(', '),
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
  final _amountInWords = TextEditingController();
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
    _amountInWords.dispose();
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
      setState(() => _items = rows);
    } on DioException {
      // Leave list empty on failure — RefreshIndicator lets them retry.
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  double get _draftTotal => _rows.fold(0, (sum, r) => sum + r.lineTotal);

  Future<void> _submit() async {
    final cleanItems = _rows
        .where((r) => r.particulars.text.trim().isNotEmpty)
        .map(
          (r) => {
            'particulars': r.particulars.text.trim(),
            'qty': r.qty.text.trim(),
            'unit_cost': r.unitCost.text.trim(),
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
      await dio.post(
        '/api/requisitions/finance',
        data: {
          'amount_in_words': _amountInWords.text.trim(),
          'items': cleanItems,
        },
      );
      setState(() {
        _formOpen = false;
        _amountInWords.clear();
        for (final r in _rows) {
          r.dispose();
        }
        _rows
          ..clear()
          ..add(_ItemDraft());
      });
      await _load();
    } on DioException catch (e) {
      final data = e.response?.data;
      setState(() {
        _error = (data is Map && data['detail'] is String)
            ? data['detail'] as String
            : 'Could not submit your requisition.';
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
            if (_loadingList)
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
              'Total: UGX ${_draftTotal.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountInWords,
            decoration: const InputDecoration(labelText: 'Amount in words (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
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
                : const Text('Submit requisition'),
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
          void refresh() => setRowState(() {});
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
                      keyboardType: TextInputType.number,
                      onChanged: (_) => refresh(),
                      decoration: const InputDecoration(labelText: 'Qty'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: row.unitCost,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => refresh(),
                      decoration: const InputDecoration(labelText: 'Unit cost'),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  row.lineTotal.toStringAsFixed(0),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: Brand.shadowCard,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UGX ${r.total.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  r.itemSummary,
                  style: const TextStyle(color: Brand.slate, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _StatusChip(status: r.status),
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
