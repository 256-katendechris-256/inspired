import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/brand.dart';

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
  const StoreRequestItemView({required this.itemDescription, required this.quantity});
  final String itemDescription;
  final String quantity;

  factory StoreRequestItemView.fromJson(Map<String, dynamic> j) => StoreRequestItemView(
    itemDescription: j['item_description'] as String? ?? '',
    quantity: j['quantity'] as String? ?? '',
  );
}

class StoreRequestView {
  const StoreRequestView({
    required this.id,
    required this.status,
    required this.items,
  });
  final int id;
  final String status;
  final List<StoreRequestItemView> items;

  factory StoreRequestView.fromJson(Map<String, dynamic> j) => StoreRequestView(
    id: j['id'] as int,
    status: j['status'] as String? ?? 'pending_verification',
    items: (j['items'] as List? ?? [])
        .map((e) => StoreRequestItemView.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
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
      await dio.post(
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
      await _load();
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
                  r.items.map((i) => i.itemDescription).join(', '),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
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
