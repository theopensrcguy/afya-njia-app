import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import 'supplier_form.dart';

/// "+255..." / "0712..." → "255712..." (for wa.me and tel:).
String? tzNumber(String? phone) {
  final d = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('0')) return '255${d.substring(1)}';
  if (d.length == 9) return '255$d';
  return d;
}

/// Wasambazaji: everyone the shop buys from, with one-tap call / WhatsApp / email.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key, required this.session});

  final Session session;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = (await _api.get('suppliers') as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _list = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final s = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => SupplierFormScreen(api: _api)));
    if (s != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: pageBackground, title: const Text('Wasambazaji')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Msambazaji mpya'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 96), children: [
                if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
                if (_list.isEmpty && _error == null)
                  const Padding(padding: EdgeInsets.all(32), child: Text('Bado hakuna msambazaji.', textAlign: TextAlign.center)),
                for (final s in _list)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: softCard(radius: 18),
                    child: ListTile(
                      title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text([s['contact_person'], s['phone'], s['location']].where((x) => x != null && '$x'.isNotEmpty).join(' · ')),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SupplierDetailScreen(session: widget.session, supplierId: asInt(s['id']))));
                        _load();
                      },
                    ),
                  ),
              ]),
            ),
    );
  }
}

/// One supplier: contacts (tap to call / WhatsApp / email) and how the shop
/// works with them.
class SupplierDetailScreen extends StatefulWidget {
  const SupplierDetailScreen({super.key, required this.session, required this.supplierId});

  final Session session;
  final int supplierId;

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  Map<String, dynamic>? _s;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.session.api.get('suppliers/${widget.supplierId}') as Map<String, dynamic>;
      if (mounted) setState(() => _s = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _edit() async {
    final s = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => SupplierFormScreen(api: widget.session.api, initial: _s)));
    if (s != null) _load();
  }

  Future<void> _open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Haikufunguka kwenye simu hii.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    Widget row(IconData icon, String label, dynamic value, {VoidCallback? onTap}) {
      if (value == null || '$value'.isEmpty) return const SizedBox.shrink();
      return ListTile(
        leading: Icon(icon, color: brandGreen),
        title: Text('$value'),
        subtitle: Text(label),
        trailing: onTap == null ? null : const Icon(Icons.open_in_new, size: 18),
        onTap: onTap,
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: Text(s == null ? 'Msambazaji' : '${s['name']}'),
        actions: [if (s != null) TextButton(onPressed: _edit, child: const Text('Hariri'))],
      ),
      body: s == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: softCard(radius: 20),
                child: Row(children: [
                  _stat('${s['deliveries'] ?? 0}', 'Mizigo'),
                  _stat(s['last_delivery_at'] == null ? '—' : timeAgo(DateTime.parse('${s['last_delivery_at']}')), 'Wa mwisho'),
                  _stat('${s['open_orders'] ?? 0}', 'Maagizo wazi'),
                  if (s['bought_90_days'] != null) _stat(formatTsh(asInt(s['bought_90_days'])), 'Siku 90'),
                ]),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: softCard(radius: 20),
                child: Column(children: [
                  row(Icons.person_outline, 'Mtu wa kuongea naye', s['contact_person']),
                  row(Icons.call_outlined, 'Simu', s['phone'],
                      onTap: tzNumber(s['phone'] as String?) == null ? null : () => _open(Uri.parse('tel:+${tzNumber(s['phone'] as String?)}'))),
                  row(Icons.chat_outlined, 'WhatsApp', s['whatsapp_number'],
                      onTap: tzNumber(s['whatsapp_number'] as String?) == null
                          ? null
                          : () => _open(Uri.parse('https://wa.me/${tzNumber(s['whatsapp_number'] as String?)}'))),
                  row(Icons.mail_outline, 'Barua pepe', s['email'], onTap: () => _open(Uri.parse('mailto:${s['email']}'))),
                  row(Icons.place_outlined, 'Mahali', s['location']),
                  row(Icons.badge_outlined, 'TIN', s['tin']),
                  row(Icons.notes, 'Maelezo', s['notes']),
                ]),
              ),
            ]),
    );
  }

  Widget _stat(String value, String label) => Expanded(
        child: Column(children: [
          Text(value, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text(label, style: const TextStyle(fontSize: 11, color: mutedText)),
        ]),
      );
}
