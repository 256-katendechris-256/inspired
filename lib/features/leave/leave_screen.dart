import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/brand.dart';
import '../../core/working_days.dart';
import '../auth/auth_controller.dart';
import '../requests/request_kit.dart';

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
    this.employeeId = '',
    this.fullName = '',
    this.department = '',
    this.reason = '',
    this.tasksDelegatedTo = '',
    this.hodDecision = 'pending',
    this.hodByName = '',
    this.hodNote = '',
    this.hrDecision = 'pending',
    this.hrByName = '',
    this.hrNote = '',
    this.reportBackOn,
    this.canDecide,
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
  final String employeeId;
  final String fullName;
  final String department;
  final String reason;
  final String tasksDelegatedTo;
  final String hodDecision;
  final String hodByName;
  final String hodNote;
  final String hrDecision;
  final String hrByName;
  final String hrNote;
  final String? reportBackOn;

  /// What the signed-in user can decide now, per the server:
  /// 'hod-decision', 'hr-decision' or null.
  final String? canDecide;

  String get reference => 'LV-${id.toString().padLeft(5, '0')}';

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
        employeeId: j['employee_id'] as String? ?? '',
        fullName: j['full_name'] as String? ?? '',
        department: j['department'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        tasksDelegatedTo: j['tasks_delegated_to'] as String? ?? '',
        hodDecision: j['hod_decision'] as String? ?? 'pending',
        hodByName: j['hod_by_name'] as String? ?? '',
        hodNote: j['hod_note'] as String? ?? '',
        hrDecision: j['hr_decision'] as String? ?? 'pending',
        hrByName: j['hr_by_name'] as String? ?? '',
        hrNote: j['hr_note'] as String? ?? '',
        reportBackOn: j['report_back_on'] as String?,
        canDecide: j['can_decide'] as String?,
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
  /// Gazetted holidays, so the day count on the form matches the one the
  /// server will store. Empty is safe — the count is then Mon–Sat only.
  Set<String> _holidays = {};

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
        dio.get('/api/leave/holidays'),
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
      final holidays = {
        for (final h in (results[2].data['holidays'] as List? ?? const []))
          (h as Map)['date'] as String,
      };
      setState(() {
        _items = rows;
        _types = types;
        _holidays = holidays;
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

  /// The server's rule: leave starts today or later, except sick leave,
  /// which may start up to a week back (it's filed on return).
  DateTime get _earliestStart {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _leaveType == 'sick' ? today.subtract(const Duration(days: 7)) : today;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final first = isStart ? _earliestStart : (_start ?? _earliestStart);
    final current = (isStart ? _start : _end) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
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

  /// Working days the picked range will cost, or null until both dates are in.
  int? get _days => _start == null || _end == null
      ? null
      : countWorkingDays(_start!, _end!, _holidays);

  /// Days away including Sundays and holidays — what they'll actually miss.
  int? get _calendarDays => _start == null || _end == null
      ? null
      : countCalendarDays(_start!, _end!);

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
      final res = await dio.post(
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
      final sent = LeaveRequestItem.fromJson(Map<String, dynamic>.from(res.data));
      unawaited(_load());
      if (mounted) {
        await showSubmittedSheet(
          context,
          title: 'Leave request ${sent.reference} submitted',
          subtitle: '${sent.leaveTypeName}, ${sent.startDate} → ${sent.endDate} · '
              '${sent.days} working day${sent.days == 1 ? '' : 's'}. '
              '${sent.status == 'pending_hr' ? 'Sent to HR.' : 'Sent to your HOD.'}',
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
            else ...[
              if (_toDecide.isNotEmpty) ...[
                requestSectionLabel('Needs your decision (${_toDecide.length})', Brand.orange),
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

  List<LeaveRequestItem> get _toDecide => _items.where((r) => r.canDecide != null).toList();
  List<LeaveRequestItem> get _others => _items.where((r) => r.canDecide == null).toList();

  Future<void> _share(BuildContext button, LeaveRequestItem r) => shareApiPdf(
        button,
        ref.read(dioProvider),
        url: '/api/leave/requests/${r.id}/pdf',
        filename: 'leave-${r.reference}.pdf',
        text: 'Leave request ${r.reference}: ${r.leaveTypeName}, '
            '${r.startDate} → ${r.endDate} (${r.days} working days)',
        subject: 'Leave request ${r.reference}',
      );

  void _openDetail(LeaveRequestItem r) => showRequestSheet(
        context,
        _LeaveDetail(item: r, onChanged: _load, onShare: _share),
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
            'New leave request',
            style: TextStyle(fontWeight: FontWeight.w700, color: Brand.ink),
          ),
          const SizedBox(height: 14),
          // What they're asking for and what it costs, side by side — the two
          // things they're actually deciding between.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _types.any((t) => t.code == _leaveType)
                      ? _leaveType
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Type of leave',
                  ),
                  items: _types
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.code,
                          child: Text(t.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _leaveType = v ?? _leaveType;
                    // A backdated sick-leave start isn't allowed for other types.
                    if (_start != null && _start!.isBefore(_earliestStart)) {
                      _start = null;
                      _end = null;
                    }
                  }),
                ),
              ),
              const SizedBox(width: 12),
              _DaysBadge(days: _days),
            ],
          ),
          if (_selectedType != null) ...[
            const SizedBox(height: 10),
            _TypeExplainer(
              type: _selectedType!,
              days: _days,
              calendarDays: _calendarDays,
            ),
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
                      r.leaveTypeName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Brand.ink,
                      ),
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
                      '${r.startDate} → ${r.endDate} · ${r.days}d',
                      style: const TextStyle(color: Brand.slate, fontSize: 12.5),
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

/// One leave request in full, and — for its HOD or HR — the decision.
class _LeaveDetail extends ConsumerStatefulWidget {
  const _LeaveDetail({required this.item, required this.onChanged, required this.onShare});
  final LeaveRequestItem item;
  final Future<void> Function() onChanged;
  final Future<void> Function(BuildContext button, LeaveRequestItem r) onShare;

  @override
  ConsumerState<_LeaveDetail> createState() => _LeaveDetailState();
}

class _LeaveDetailState extends ConsumerState<_LeaveDetail> {
  LeaveRequestItem get r => widget.item;
  late final _cover = TextEditingController(text: widget.item.tasksDelegatedTo);
  final _entitlement = TextEditingController();
  final _balance = TextEditingController();
  DateTime? _reportBack;

  @override
  void initState() {
    super.initState();
    // Default: the first working day after the leave ends (Mon–Sat).
    final end = DateTime.tryParse(r.endDate);
    if (end != null) {
      var d = end.add(const Duration(days: 1));
      if (d.weekday == DateTime.sunday) d = d.add(const Duration(days: 1));
      _reportBack = d;
    }
  }

  @override
  void dispose() {
    _cover.dispose();
    _entitlement.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<String?> _decide(String decision, String note) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final hr = r.canDecide == 'hr-decision';
    try {
      await ref.read(dioProvider).patch(
        '/api/leave/requests/${r.id}/${r.canDecide}',
        data: {
          'decision': decision,
          'note': note,
          if (!hr && _cover.text.trim().isNotEmpty) 'tasks_delegated_to': _cover.text.trim(),
          if (hr && decision == 'approved') ...{
            if (_entitlement.text.trim().isNotEmpty) 'leave_entitlement_days': _entitlement.text.trim(),
            if (_balance.text.trim().isNotEmpty) 'leave_balance_days': _balance.text.trim(),
            if (_reportBack != null) 'report_back_on': DateFormat('yyyy-MM-dd').format(_reportBack!),
          },
        },
      );
      await widget.onChanged();
      nav.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(switch ((decision, hr)) {
          ('rejected', _) => '${r.reference} declined.',
          (_, false) => '${r.reference} recommended — sent to HR.',
          _ => '${r.reference} approved.',
        }),
      ));
      return null;
    } catch (e) {
      return apiError(e, 'That decision wasn\'t saved.');
    }
  }

  List<Widget> _hrFields() => [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _entitlement,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Entitlement (days)', filled: true, fillColor: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _balance,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Balance (days)', filled: true, fillColor: Colors.white),
              ),
            ),
          ],
        ),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _reportBack ?? now,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 2),
            );
            if (picked != null) setState(() => _reportBack = picked);
          },
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Report back on',
              prefixIcon: Icon(Icons.calendar_today_outlined, size: 18),
              filled: true,
              fillColor: Colors.white,
            ),
            child: Text(_reportBack == null ? '—' : DateFormat('EEE d MMM yyyy').format(_reportBack!)),
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final dio = ref.read(dioProvider);
    final hr = r.canDecide == 'hr-decision';
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
        const SizedBox(height: 14),
        Text(r.leaveTypeName, style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.ink)),
        Text(
          '${r.startDate} → ${r.endDate} · ${r.days} working day${r.days == 1 ? '' : 's'}',
          style: const TextStyle(color: Brand.slate),
        ),
        if (r.reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Reason: ${r.reason}', style: const TextStyle(color: Brand.ink)),
          ),
        if (r.tasksDelegatedTo.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Covering: ${r.tasksDelegatedTo}', style: const TextStyle(color: Brand.ink)),
          ),
        if (r.reportBackOn != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Report back on ${r.reportBackOn}', style: const TextStyle(color: Brand.ink)),
          ),
        const SizedBox(height: 16),
        StageLine(
          who: 'Head of Department',
          decision: r.hodDecision,
          note: r.hodNote,
          by: r.hodByName,
          approvedLabel: 'Recommended',
        ),
        StageLine(who: 'HR', decision: r.hrDecision, note: r.hrNote, by: r.hrByName),
        if (r.canDecide != null)
          DecisionPanel(
            title: hr ? 'Your decision (HR)' : 'Your decision (HOD)',
            what: r.reference,
            approveLabel: hr ? 'Approve' : 'Recommend',
            fields: hr
                ? _hrFields()
                : [
                    TextField(
                      controller: _cover,
                      decoration: const InputDecoration(
                        labelText: 'Who covers their tasks?',
                        hintText: 'e.g. Grace (site supervision)',
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                  ],
            onDecide: _decide,
          ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () => openApiFile(context, dio, '/api/leave/requests/${r.id}/pdf', 'leave-${r.reference}.pdf'),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Open form (PDF)'),
        ),
        const SizedBox(height: 8),
        Builder(
          builder: (btn) => OutlinedButton.icon(
            onPressed: () => widget.onShare(btn, r),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Share'),
          ),
        ),
      ],
    );
  }
}

/// The cost of the request, sat beside the type it applies to. Blank until
/// both dates are picked, so it never shows a confident "0".
class _DaysBadge extends StatelessWidget {
  const _DaysBadge({required this.days});
  final int? days;

  @override
  Widget build(BuildContext context) {
    final known = days != null;
    return Container(
      width: 84,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: known ? Brand.greenWash : Brand.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: known ? Brand.green.withValues(alpha: 0.3) : Brand.line),
      ),
      child: Column(
        children: [
          Text(
            known ? '${days!}' : '—',
            style: TextStyle(
              fontSize: 24,
              height: 1.05,
              fontWeight: FontWeight.w700,
              color: known ? Brand.green : Brand.mute,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            known && days == 1 ? 'working day' : 'working days',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9.5, color: Brand.slate, height: 1.1),
          ),
        ],
      ),
    );
  }
}

/// What this kind of leave is for, what the picked dates will cost, and where
/// the employee stands on their entitlement — the plain-language note the
/// paper form never had room for.
/// What this kind of leave is for, what the picked dates will cost, and where
/// the employee stands on their entitlement — the plain-language note the
/// paper form never had room for.
class _TypeExplainer extends StatelessWidget {
  const _TypeExplainer({
    required this.type,
    required this.days,
    required this.calendarDays,
  });
  final LeaveTypeOption type;
  final int? days;
  final int? calendarDays;

  /// Spelled out only when it differs from the working-day count, so we don't
  /// state the obvious for a range with no Sunday or holiday in it.
  String? get _spanNote {
    if (days == null || calendarDays == null) return null;
    if (calendarDays == days) return null;
    final rest = calendarDays! - days!;
    return 'Away $calendarDays days in all — $rest '
        '${rest == 1 ? 'is a rest day or holiday' : 'are rest days or holidays'}, '
        'which you are not charged for.';
  }

  /// Warns before they submit something their balance cannot cover.
  String? get _overdraw {
    if (days == null || type.remaining == null) return null;
    if (days! <= type.remaining!) return null;
    final over = days! - type.remaining!;
    return 'That is $over day${over == 1 ? '' : 's'} more than you have left. '
        'HR has to decide whether to allow it.';
  }

  @override
  Widget build(BuildContext context) {
    final span = _spanNote;
    final over = _overdraw;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (type.description.isNotEmpty) ...[
            Text(
              type.description,
              style: const TextStyle(
                color: Brand.ink,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _Line(
            icon: Icons.account_balance_wallet_outlined,
            text: type.balanceLine,
            color: Brand.slate,
          ),
          if (span != null) ...[
            const SizedBox(height: 6),
            _Line(
              icon: Icons.event_busy_outlined,
              text: span,
              color: Brand.slate,
            ),
          ],
          if (over != null) ...[
            const SizedBox(height: 6),
            _Line(
              icon: Icons.warning_amber_rounded,
              text: over,
              color: Brand.orange,
            ),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 11.5, height: 1.35),
          ),
        ),
      ],
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
