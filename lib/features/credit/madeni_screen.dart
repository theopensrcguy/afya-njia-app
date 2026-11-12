import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import 'customer_picker.dart';

/// Madeni: who owes the shop, receiving their payments, and (for whoever may
/// approve credit) approving customers and setting their optional limit.
///
/// Same rules as the web page (App\Services\CreditService on the server):
/// what someone owes is always worked out from their credit sales and
/// payments, never typed in.
class MadeniScreen extends StatefulWidget {
  const MadeniScreen({super.key, required this.session});

  final Session session;

  @override
  State<MadeniScreen> createState() => _MadeniScreenState();
}

class _MadeniScreenState extends State<MadeniScreen> {
  List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic> _summary = const {};
  String _filter = 'owing'; // owing | pending | all
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.session.api;
  bool get _canApprove => widget.session.user!.can(Perm.manageCredit);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get('customers') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _customers = (r['customers'] as List).cast<Map<String, dynamic>>();
        _summary = (r['summary'] as Map).cast<String, dynamic>();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _shown => _customers.where((c) {
        final owes = (c['owes'] as num?)?.toInt() ?? 0;
        return switch (_filter) { 'owing' => owes > 0, 'pending' => c['credit_status'] == 'pending', _ => true };
      }).toList();

  Future<void> _open(Map<String, dynamic> c) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerScreen(session: widget.session, id: c['id'] as int)));
    _load();
  }

  Future<void> _add() async {
    final c = await addCustomer(context, api: _api, canApprove: _canApprove);
    if (c != null) {
      setState(() => _filter = 'all');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = (_summary['pending'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Madeni')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add_alt_1_outlined), label: const T('Mteja mpya')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
                Card(
                  color: Colors.white,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const T('Wanadaiwa jumla', style: TextStyle(color: mutedText)),
                      Text(formatTsh((_summary['total'] as num?)?.toInt() ?? 0), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                      Text(tr('wateja :n wanadaiwa', {'n': _summary['customers'] ?? 0}), style: const TextStyle(color: mutedText)),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final (k, label) in [('owing', tr('Wanaodaiwa')), ('pending', pending > 0 ? '${tr('Wanasubiri idhini')} · $pending' : tr('Wanasubiri idhini')), ('all', tr('Wote'))])
                    ChoiceChip(label: Text(label), selected: _filter == k, onSelected: (_) => setState(() => _filter = k)),
                ]),
                const SizedBox(height: 8),
                if (_shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_filter == 'owing' ? tr('Hakuna anayedaiwa sasa.') : tr('Hakuna mteja hapa.'), textAlign: TextAlign.center, style: const TextStyle(color: mutedText)),
                  ),
                for (final c in _shown)
                  Card(
                    color: Colors.white,
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => _open(c),
                      title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(customerLine(c), style: TextStyle(color: c['credit_status'] == 'approved' ? mutedText : warnAmber)),
                      trailing: _owes(c),
                    ),
                  ),
              ]),
            ),
    );
  }
}

/// "TSh 4,500", or "salio 1,000" when the shop owes them (a returned sale after they paid).
Widget _owes(Map<String, dynamic> c) {
  final owes = (c['owes'] as num?)?.toInt() ?? 0;
  if (owes > 0) return Text(formatTsh(owes), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15));
  if (owes < 0) return Text(tr('Ana salio :a', {'a': formatTsh(-owes)}), style: const TextStyle(color: mutedText, fontSize: 12));
  return const Text('—', style: TextStyle(color: mutedText));
}

/// One customer: what they owe, their account, receive a payment, approve / limit.
class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  Map<String, dynamic>? _c;
  String? _error;

  ApiClient get _api => widget.session.api;
  bool get _canApprove => widget.session.user!.can(Perm.manageCredit);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _api.get('customers/${widget.id}') as Map<String, dynamic>;
      if (mounted) setState(() => _c = c);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? dangerRed : null));
  }

  Future<void> _pay() async {
    final c = _c!;
    final owes = (c['owes'] as num).toInt();
    final amount = TextEditingController(text: '$owes');
    var method = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, set) => AlertDialog(
          title: Text(tr('Pokea malipo: :name', {'name': c['name']})),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Anadaiwa :a.', {'a': formatTsh(owes)})),
            const SizedBox(height: 8),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Kiasi (TSh)'))),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 'cash', label: T('Taslimu')), ButtonSegment(value: 'mobile', label: T('Simu'))],
              selected: {method},
              onSelectionChanged: (s) => set(() => method = s.first),
            ),
            const SizedBox(height: 8),
            const T('Taslimu inaingia kwenye droo ya zamu iliyo wazi.', style: TextStyle(color: mutedText, fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const T('Ghairi')),
            FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const T('Pokea')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await _api.post('customers/${c['id']}/payments', {
        'amount': int.tryParse(amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
        'method': method,
      }) as Map<String, dynamic>;
      final left = (r['owes'] as num).toInt();
      _toast(left > 0 ? tr('Malipo yamepokelewa. Bado anadaiwa :a.', {'a': formatTsh(left)}) : tr('Malipo yamepokelewa. Deni limekwisha.'));
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _approve({required String status}) async {
    final c = _c!;
    final limit = TextEditingController(text: c['credit_limit'] == null ? '' : '${c['credit_limit']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(status == 'approved' ? tr('Idhinisha :name kukopa?', {'name': c['name']}) : '${c['name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: limit,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('Kikomo cha deni (TSh, si lazima)'), hintText: tr('hakuna kikomo')),
          ),
          const SizedBox(height: 6),
          const T('Kiasi cha juu anachoweza kudaiwa kwa wakati mmoja. Acha wazi kwa bila kikomo.', style: TextStyle(color: mutedText, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const T('Ghairi')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: Text(status == 'approved' ? tr('Idhinisha') : tr('Hifadhi'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final digits = limit.text.replaceAll(RegExp(r'\D'), '');
      await _api.patch('customers/${c['id']}', {'credit_status': status, 'credit_limit': digits.isEmpty ? null : int.parse(digits)});
      _toast(tr('Imehifadhiwa.'));
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _block() async {
    try {
      await _api.patch('customers/${_c!['id']}', {'credit_status': 'blocked'});
      _toast(tr('Imehifadhiwa.'));
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: pageBackground),
        body: Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const CircularProgressIndicator()),
      );
    }
    final owes = (c['owes'] as num).toInt();
    final statement = (c['statement'] as List).cast<Map<String, dynamic>>();
    final phone = c['phone'] == null ? '' : '0${'${c['phone']}'.substring(3)}';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: Text('${c['name']}'),
        actions: [
          if (_canApprove)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'block' ? _block() : _approve(status: 'approved'),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'limit', child: T(c['credit_status'] == 'approved' ? 'Badilisha kikomo' : 'Idhinisha')),
                if (c['credit_status'] != 'blocked') const PopupMenuItem(value: 'block', child: T('Zuia kukopa')),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text([if (phone.isNotEmpty) phone, '${c['credit_status_label']}', if (c['credit_limit'] != null) tr('kikomo :a', {'a': formatTsh(c['credit_limit'] as int)})].join(' · '),
              style: const TextStyle(color: mutedText)),
          const SizedBox(height: 8),
          Row(children: [
            const T('Anadaiwa ', style: TextStyle(fontSize: 18)),
            _owes(c),
          ]),
          const SizedBox(height: 12),
          if (c['credit_status'] == 'pending' && _canApprove)
            FilledButton.icon(onPressed: () => _approve(status: 'approved'), icon: const Icon(Icons.verified_outlined), label: const T('Idhinisha')),
          if (owes > 0)
            FilledButton.icon(onPressed: _pay, icon: const Icon(Icons.payments_outlined), label: const T('Pokea malipo')),
          const SizedBox(height: 16),
          const T('Historia', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          if (statement.isEmpty) const Padding(padding: EdgeInsets.all(16), child: T('Bado hakuna deni wala malipo.', style: TextStyle(color: mutedText))),
          for (final s in statement)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(s['kind'] == 'sale' ? Icons.shopping_bag_outlined : Icons.payments_outlined,
                  color: s['kind'] == 'sale' ? warnAmber : brandGreen),
              title: Text(s['kind'] == 'sale' ? '${tr('Deni')} · ${s['receipt_number']}' : '${tr('Malipo')} · ${paymentLabels[s['method']] ?? s['method']}'),
              subtitle: Text('${timeAgo(DateTime.parse('${s['at']}').toLocal())} · ${s['by'] ?? ''}'),
              trailing: Text('${s['kind'] == 'sale' ? '+' : '−'}${formatTsh((s['amount'] as num).toInt())}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: s['kind'] == 'sale' ? null : brandGreen)),
            ),
        ]),
      ),
    );
  }
}
