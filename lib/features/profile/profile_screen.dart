import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/brand.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _saved;

  String _employeeId = '';
  String _fullName = '';
  String _role = '';
  String _department = '';

  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _dob = TextEditingController();
  final _nokName = TextEditingController();
  final _nokPhone = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    _dob.dispose();
    _nokName.dispose();
    _nokPhone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/api/auth/me');
      final d = Map<String, dynamic>.from(res.data);
      _employeeId = d['employee_id'] as String? ?? '';
      _fullName = d['full_name'] as String? ?? '';
      _role = d['role'] as String? ?? '';
      _department = d['department'] as String? ?? '';
      _email.text = d['email'] as String? ?? '';
      _phone.text = d['phone'] as String? ?? '';
      _dob.text = d['date_of_birth'] as String? ?? '';
      _nokName.text = d['emergency_contact_name'] as String? ?? '';
      _nokPhone.text = d['emergency_contact_phone'] as String? ?? '';
    } on DioException {
      setState(() => _error = 'Could not load your profile.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(_dob.text) ?? DateTime(now.year - 25);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: now,
    );
    if (picked != null) {
      _dob.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _saved = null;
    });
    try {
      final dio = ref.read(dioProvider);
      await dio.patch(
        '/api/auth/me',
        data: {
          'email': _email.text.trim(),
          'phone': _phone.text.trim(),
          'date_of_birth': _dob.text.trim(),
          'emergency_contact_name': _nokName.text.trim(),
          'emergency_contact_phone': _nokPhone.text.trim(),
        },
      );
      setState(() => _saved = 'Saved.');
    } on DioException catch (e) {
      final data = e.response?.data;
      setState(() {
        _error = (data is Map && data['detail'] is String)
            ? data['detail'] as String
            : 'Could not save your changes.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _roleLabel(String role) => switch (role) {
    'hod' => 'Head of Department',
    'hr' => 'Human Resources',
    'admin' => 'System Admin',
    'exec' => 'Executive',
    _ => 'Staff',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.canvas,
      appBar: AppBar(
        title: const Text('Profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Brand.green))
          : RefreshIndicator(
              color: Brand.green,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _IdentityCard(
                    employeeId: _employeeId,
                    fullName: _fullName,
                    roleLabel: _roleLabel(_role),
                    department: _department,
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('Contact details'),
                  const SizedBox(height: 10),
                  _Card(
                    children: [
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _dob,
                        readOnly: true,
                        onTap: _pickDob,
                        decoration: const InputDecoration(
                          labelText: 'Date of birth',
                          prefixIcon: Icon(Icons.cake_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('Next of kin / emergency contact'),
                  const SizedBox(height: 10),
                  _Card(
                    children: [
                      TextField(
                        controller: _nokName,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nokPhone,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: const TextStyle(color: Brand.red)),
                  ],
                  if (_saved != null) ...[
                    const SizedBox(height: 14),
                    Text(_saved!, style: const TextStyle(color: Brand.green)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save changes'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/reset-password'),
                    icon: const Icon(Icons.lock_reset),
                    label: const Text('Change password'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.w700,
      color: Brand.ink,
      fontSize: 15,
    ),
  );
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.employeeId,
    required this.fullName,
    required this.roleLabel,
    required this.department,
  });

  final String employeeId;
  final String fullName;
  final String roleLabel;
  final String department;

  @override
  Widget build(BuildContext context) {
    final initials = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join()
        .toUpperCase();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: Brand.shadowCard,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Brand.greenWash,
              shape: BoxShape.circle,
            ),
            child: Text(
              initials.isEmpty ? '?' : initials,
              style: const TextStyle(
                color: Brand.green,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Brand.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$employeeId · $department · $roleLabel',
                  style: const TextStyle(color: Brand.slate, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: Brand.shadowCard,
      ),
      child: Column(children: children),
    );
  }
}
