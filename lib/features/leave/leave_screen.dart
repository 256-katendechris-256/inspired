import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/brand.dart';

/// A kind of leave this employee may ask for, as configured by HR. The
/// server has already applied the gender rule (a man never sees maternity
/// leave, a woman never sees paternity) and worked out this year's balance.
class LeaveTypeOption {
  const LeaveTypeOption({
    required this.code,
    required this.name,
    required this.description,
    required this.daysPerYear,
    required this.requiresReason,
    required this.allowed,
    required this.unavailableReason,
    required this.used,
    required this.pending,
    required this.remaining,
  });

  final String code;
  final String name;
  final String description;
  final int daysPerYear;
  final bool requiresReason;
  final bool allowed;
  final String unavailableReason;
  final int used;
  final int pending;
  final int? remaining;

  factory LeaveTypeOption.fromJson(Map<String, dynamic> j) {
    final bal = j['balance'] is Map ? Map<String, dynamic>.from(j['balance']) : const {};
    return LeaveTypeOption(
      code: j['code'] as String,
      name: j['name'] as String? ?? j['code'] as String,
      description: j['description'] as String? ?? '',
      daysPerYear: j['days_per_year'] as int? ?? 0,
      requiresReason: j['requires_reason'] as bool? ?? false,
      allowed: j['allowed'] as bool? ?? true,
      unavailableReason: j['unavailable_reason'] as String? ?? '',
      used: bal['used'] as int? ?? 0,
      pending: bal['pending'] as int? ?? 0,
      remaining: bal['remaining'] as int?,
    );
  }

  String get balanceLine {
    if (daysPerYear == 0) return 'No fixed entitlement — HR decides case by case.';
    final parts = <String>['$daysPerYear days a year'];
    if (used > 0) parts.add('$used used');
    if (pending > 0) parts.add('$pending awaiting approval');
    if (remaining != null) parts.add('$remaining left');
    return parts.join(' · ');
  }
}

class LeaveRequestItem {
  const LeaveRequestItem({
    required this.id,
    required this.leaveType,
    required this.leaveTypeName,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.status,
    required this.hodBy,
    required this.hrBy,
  });

  final int id;
  final String leaveType;
  final String leaveTypeName;
  final String startDate;
  final String endDate;
  final int days;
  final String status;
  final String? hodBy;
  final String? hrBy;

  factory LeaveRequestItem.fromJson(Map<String, dynamic> j) =>
      LeaveRequestItem(
        id: j['id'] as int,
        leaveType: j['leave_type'] as String? ?? 'other',
        leaveTypeName: j['leave_type_name'] as String? ??
            (j['leave_type'] as String? ?? 'Other'),
        startDate: j['start_date'] as String? ?? '',
        endDate: j['end_date'] as String? ?? '',
        days: j['days'] as int? ?? 0,
        status: j['status'] as String? ?? 'pending_hod',
        hodBy: j['hod_by'] as String?,
        hrBy: j['hr_by'] as String?,
      );
}

class LeaveScreen extends ConsumerStatefulWidget {
  const LeaveScreen({super.key});

  @override
  ConsumerState<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends ConsumerState<LeaveScreen> {
  final _dateFmt = DateFormat('yyyy-MM-dd');

  bool _loadingList = true;
  List<LeaveRequestItem> _items = [];
  List<LeaveTypeOption> _types = [];

  bool _formOpen = false;
  String _leaveType = 'annual';
  DateTime? _start;
  DateTime? _end;
  final _reason = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadingList = true);
    try {
      final dio = ref.read(dioProvider);
      final results = await Future.wait([
        dio.get('/api/leave/requests'),
        dio.get('/api/leave/types'),
      ]);
      final rows = (results[0].data['requests'] as List)
          .map((e) => LeaveRequestItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      // Only the types this person may actually take — the rest would just
      // be a form error waiting to happen.
      final types = (results[1].data['types'] as List)
          .map((e) => LeaveTypeOption.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.allowed)
          .toList();
      setState(() {
        _items = rows;
        _types = types;
        if (types.isNotEmpty && !types.any((t) => t.code == _leaveType)) {
          _leaveType = types.first.code;
        }
      });
    } on DioException {
      // Leave list empty on failure — the RefreshIndicator lets them retry.
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _start : _end) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  LeaveTypeOption? get _selectedType {
    for (final t in _types) {
      if (t.code == _leaveType) return t;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_start == null || _end == null) {
      setState(() => _error = 'Pick a start and end date.');
      return;
    }
    final sel = _selectedType;
    if (sel != null && sel.requiresReason && _reason.text.trim().isEmpty) {
      setState(() => _error = '${sel.name} needs a short reason.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      await dio.post(
        '/api/leave/requests',
        data: {
          'leave_type': _leaveType,
          'start_date': _dateFmt.format(_start!),
          'end_date': _dateFmt.format(_end!),
          'reason': _reason.text.trim(),
        },
      );
      setState(() {
        _formOpen = false;
        _start = null;
        _end = null;
        _reason.clear();
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
        title: const Text('Leave requests'),
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
                child: Center(
                  child: CircularProgressIndicator(color: Brand.green),
                ),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    'No leave requests yet.',
                    style: TextStyle(color: Brand.slate),
                  ),
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
            'New leave request',
            style: TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _types.any((t) => t.code == _leaveType)
                ? _leaveType
                : null,
            decoration: const InputDecoration(labelText: 'Type of leave'),
            items: _types
                .map(
                  (t) => DropdownMenuItem(value: t.code, child: Text(t.name)),
                )
                .toList(),
            onChanged: (v) => setState(() => _leaveType = v ?? _leaveType),
          ),
          if (_selectedType != null) ...[
            const SizedBox(height: 8),
            _TypeExplainer(type: _selectedType!),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DatePickerField(
                  label: 'Start date',
                  value: _start,
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DatePickerField(
                  label: 'End date',
                  value: _end,
                  onTap: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: (_selectedType?.requiresReason ?? false)
                  ? 'Reason (required)'
                  : 'Reason (optional)',
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Your HOD will decide who covers your tasks while you\'re away.',
              style: TextStyle(color: Brand.slate, fontSize: 12),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Brand.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit request'),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(LeaveRequestItem r) {
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
                  r.leaveTypeName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Brand.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${r.startDate} → ${r.endDate} · ${r.days}d',
                  style: const TextStyle(color: Brand.slate, fontSize: 12.5),
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

/// What this kind of leave is for and where the employee stands on it —
/// the plain-language note the paper form never had room for.
class _TypeExplainer extends StatelessWidget {
  const _TypeExplainer({required this.type});
  final LeaveTypeOption type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.green.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (type.description.isNotEmpty)
            Text(
              type.description,
              style: const TextStyle(color: Brand.ink, fontSize: 12.5, height: 1.35),
            ),
          if (type.description.isNotEmpty) const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.event_available_outlined, size: 15, color: Brand.green),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  type.balanceLine,
                  style: const TextStyle(
                    color: Brand.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? ''
        : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}';
    return TextField(
      controller: TextEditingController(text: text),
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
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
      'pending_hr' => (Brand.blue, 'Pending HR'),
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
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
      ),
    );
  }
}
