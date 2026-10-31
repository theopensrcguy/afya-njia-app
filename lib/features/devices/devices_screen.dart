import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/session.dart';

/// Owner only: phones allowed to use the pharmacy.
///
/// Waiting phones are on top with their 6-digit number. The owner checks it
/// matches what the helper's phone shows, then approves. Approved phones can
/// be removed; access stops on that phone immediately.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.session});

  final Session session;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;
  String? _error;
  int? _busyId; // the device being approved/removed, to show a spinner on its row

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await _api.get('devices') as List<dynamic>;
      if (!mounted) return;
      setState(() => _devices = data.cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> device) async {
    await _act(device, 'approve', 'Simu imeidhinishwa.');
  }

  Future<void> _revoke(Map<String, dynamic> device) async {
    // Removing is serious: confirm first.
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ondoa simu hii?'),
        content: Text('${device['name']} haitaweza kutumia Afya Njia tena. Itahitaji idhini mpya.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Hapana')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: dangerRed),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ondoa'),
          ),
        ],
      ),
    );
    if (sure == true) await _act(device, 'revoke', 'Simu imeondolewa.');
  }

  Future<void> _act(Map<String, dynamic> device, String action, String doneMessage) async {
    final id = device['id'] as int;
    setState(() => _busyId = id);
    try {
      await _api.post('devices/$id/$action');
      _snack(doneMessage);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _snack(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: isError ? dangerRed : null));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simu zinazoruhusiwa')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              // Pull down to refresh: the helper's request appears the moment he types his PIN.
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
                  if (_devices.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Text('Hakuna simu bado.', textAlign: TextAlign.center),
                    ),
                  for (final d in _devices) _deviceCard(d),
                ],
              ),
            ),
    );
  }

  Widget _deviceCard(Map<String, dynamic> d) {
    final status = d['status'] as String;
    final isThis = d['is_this_device'] == true;
    final busy = _busyId == d['id'];

    final (label, color) = switch (status) {
      'pending' => ('Inasubiri idhini', warnAmber),
      'approved' => ('Imeidhinishwa', brandGreen),
      _ => ('Imeondolewa', mutedText),
    };

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: status == 'pending' ? warnAmber : const Color(0xFFE6E8E2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${d['name']}${isThis ? ' (simu hii)' : ''}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Imeombwa na ${d['requested_by']}', style: const TextStyle(color: mutedText, fontSize: 13)),
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              const Text('Hakikisha namba hii inalingana na iliyo kwenye simu yake:', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                d['pairing_code'] as String? ?? '',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 4),
              ),
            ],
            if (status != 'revoked' && !isThis) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: busy
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : status == 'pending'
                        ? FilledButton.icon(
                            onPressed: () => _approve(d),
                            icon: const Icon(Icons.check),
                            label: const Text('Idhinisha'),
                          )
                        : OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: dangerRed),
                            onPressed: () => _revoke(d),
                            icon: const Icon(Icons.block),
                            label: const Text('Ondoa'),
                          ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
