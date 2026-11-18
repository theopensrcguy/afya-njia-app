import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/loader.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import 'customer_consent.dart';
import 'register_customer.dart';

/// Wateja: who to remind today that their medicine is running out, reminders
/// coming up, and the customers who agreed to be kept on record, with what
/// they bought. A customer is added here (Sajili mteja) or at the till, if they agree.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, required this.session});

  final Session session;

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic> _board = const {};
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.get('customer-records') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _customers = (r['customers'] as List).cast<Map<String, dynamic>>();
        _board = (r['board'] as Map).cast<String, dynamic>();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _groups(String key) => ((_board[key] as List?) ?? const []).cast<Map<String, dynamic>>();

  void _say(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _act(Future<dynamic> Function() call, String done) async {
    try {
      await call();
      _say(done);
      _load();
    } on ApiException catch (e) {
      _say(e.message);
    }
  }

  /// Opens WhatsApp on the customer's chat with the message typed in; the
  /// staff member sends it, then says so.
  Future<void> _whatsapp(Map<String, dynamic> g) async {
    final c = (g['customer'] as Map).cast<String, dynamic>();
    final uri = Uri.parse('https://wa.me/${c['phone']}?text=${Uri.encodeComponent('${g['message']}')}');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!opened) return _say(tr('WhatsApp haikufunguka kwenye simu hii.'));
    final sent = await confirmDialog(context,
        title: tr('Umemtumia?'),
        message: tr('Ukishautuma ujumbe kwenye WhatsApp, bonyeza "Nimemtumia" ili asionekane tena kwenye orodha ya leo.'),
        confirm: tr('Nimemtumia'));
    if (sent == true) await _act(() => _api.post('customers/${c['id']}/reminded', {'via': 'whatsapp'}), tr('Amekumbushwa.'));
  }

  Future<void> _sms(Map<String, dynamic> g) async {
    final c = (g['customer'] as Map).cast<String, dynamic>();
    final ok = await confirmDialog(context,
        title: tr('Tuma SMS kwa :name?', {'name': c['name']}),
        message: '${g['message']}\n\n${tr('SMS inalipiwa na duka (kupitia mtoa huduma wa SMS).')}',
        confirm: tr('Tuma SMS'));
    if (ok == true) await _act(() => _api.post('customers/${c['id']}/reminded', {'via': 'sms'}), tr('SMS imetumwa.'));
  }

  Future<void> _skip(Map<String, dynamic> r) async {
    final ok = await confirmDialog(context,
        title: tr('Ondoa kikumbusho hiki'), message: tr('Ondoa kikumbusho cha :p?', {'p': r['product']}), confirm: tr('Ondoa'), danger: true);
    if (ok == true) await _act(() => _api.delete('refill-reminders/${r['id']}'), tr('Kikumbusho kimeondolewa.'));
  }

  Future<void> _open(Map<String, dynamic> c) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HistorySheet(api: _api, customer: c),
    );
    // Consent or reminders may have changed in the sheet.
    if (changed == true || mounted) _load();
  }

  List<Map<String, dynamic>> get _shown {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return _customers;
    final digits = q.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0'), '');
    return _customers.where((c) => '${c['name']}'.toLowerCase().contains(q) || (digits.length >= 3 && '${c['phone'] ?? ''}'.contains(digits))).toList();
  }

  @override
  Widget build(BuildContext context) {
    final due = _groups('due');
    final upcoming = _groups('upcoming');
    final sent = _groups('sent');
    final today = '${_board['today'] ?? ''}';
    return Scaffold(
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Wateja', style: TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          if (await registerCustomer(context, api: _api) && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: T('Mteja amesajiliwa.')));
            _load();
          }
        },
        backgroundColor: brandGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const T('Sajili mteja'),
      ),
      body: _loading
          ? const Center(child: AfyaLoader())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: dangerRed))))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                    _title(tr('Wa kukumbushwa leo'), due.length),
                    const T('Ujumbe hautaji jina la dawa: simu inaweza kusomwa na mtu mwingine.', style: TextStyle(color: mutedText, fontSize: 13)),
                    const SizedBox(height: 6),
                    if (due.isEmpty) _empty(tr('Hakuna wa kukumbushwa leo.')),
                    for (final g in due)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${g['customer']['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            Text(phoneText(g['customer']['phone']), style: const TextStyle(color: mutedText)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              for (final r in (g['reminders'] as List).cast<Map<String, dynamic>>())
                                InputChip(
                                  label: Text('${r['product']} · ${'${r['runs_out_on']}'.compareTo(today) < 0 ? tr('iliisha :d', {'d': dayText('${r['runs_out_on']}')}) : tr('inaisha :d', {'d': dayText('${r['runs_out_on']}')})}',
                                      style: const TextStyle(fontSize: 13)),
                                  onDeleted: () => _skip(r),
                                  deleteButtonTooltipMessage: tr('Ondoa kikumbusho hiki'),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ]),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              FilledButton.icon(onPressed: () => _whatsapp(g), icon: const Icon(Icons.chat_outlined, size: 18), label: const T('Mkumbushe kwa WhatsApp')),
                              if (_board['sms'] == true) OutlinedButton(onPressed: () => _sms(g), child: const T('Tuma SMS')),
                            ]),
                          ]),
                        ),
                      ),
                    if (upcoming.isNotEmpty) ...[
                      _title(tr('Vikumbusho vinavyokuja'), upcoming.length),
                      for (final g in upcoming) _slim(g, tr('atakumbushwa :d', {'d': dayText('${g['due_on']}')})),
                    ],
                    if (sent.isNotEmpty) ...[
                      _title(tr('Wamekumbushwa, hawajarudi'), sent.length),
                      for (final g in sent)
                        _slim(g, tr('alikumbushwa :d', {'d': dayText(parseDate(g['sent_at'])?.toLocal().toIso8601String())})),
                    ],
                    _title(tr('Wateja waliokubali'), _customers.length),
                    if (_customers.isEmpty)
                      _empty(tr('Bado hakuna mteja aliyekubali. Kwenye kikapu, bonyeza "Weka mteja" kabla ya kukamilisha mauzo.'))
                    else ...[
                      TextField(
                        controller: _q,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Tafuta mteja: jina au simu…'), isDense: true),
                      ),
                      for (final c in _shown)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text([
                            phoneText(c['phone']),
                            tr('manunuzi :n', {'n': c['sales']}),
                            if (asInt(c['reminders']) > 0) tr('vikumbusho :n', {'n': c['reminders']}),
                          ].where((x) => x.isNotEmpty).join(' · ')),
                          trailing: Text(formatTsh(asInt(c['spent'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                          onTap: () => _open(c),
                        ),
                    ],
                    const SizedBox(height: 16),
                    const T('Anachonunua mtu duka la dawa ni taarifa ya afya yake. Zinahifadhiwa kwa aliyekubali tu, na mteja akisema ACHA, fungua jina lake uondoe ridhaa yake.',
                        style: TextStyle(color: mutedText, fontSize: 12)),
                  ]),
                ),
    );
  }

  Widget _title(String text, int n) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text('$text · $n', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _empty(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(text, style: const TextStyle(color: mutedText)));

  Widget _slim(Map<String, dynamic> g, String when) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text('${g['customer']['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text((g['reminders'] as List).map((r) => r['product']).join(', ')),
        trailing: Text(when, style: const TextStyle(color: mutedText)),
      );
}

/// One customer: what they bought here (newest first), their waiting
/// reminders, and "Ondoa ridhaa" for when they no longer want to be on record.
class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.api, required this.customer});

  final ApiClient api;
  final Map<String, dynamic> customer;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  Map<String, dynamic>? _h;
  String? _error;
  late bool _remind = customerWantsReminders(widget.customer);

  /// Reminders are a second, optional yes: on or off any time.
  Future<void> _setRemind(bool on) async {
    setState(() => _remind = on);
    try {
      await widget.api.patch('customers/${widget.customer['id']}/reminders', {'on': on});
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _remind = !on;
        _error = e.message;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get('customers/${widget.customer['id']}/history') as Map<String, dynamic>;
      if (mounted) setState(() => _h = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _removeConsent() async {
    final ok = await confirmDialog(context,
        title: tr('Ondoa ridhaa'),
        message: tr(':name hataki tena kumbukumbu zake? Hatakumbushwa tena, na historia yake haitaonekana.', {'name': widget.customer['name']}),
        confirm: tr('Ondoa ridhaa'),
        danger: true);
    if (ok != true) return;
    try {
      await widget.api.post('customers/${widget.customer['id']}/consent', {'consent': false});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sales = ((_h?['sales'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final reminders = ((_h?['reminders'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${widget.customer['name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(phoneText(widget.customer['phone']), style: const TextStyle(color: mutedText)),
              ]),
            ),
            TextButton(onPressed: _removeConsent, style: TextButton.styleFrom(foregroundColor: dangerRed), child: const T('Ondoa ridhaa')),
          ]),
        ),
        SwitchListTile(
          value: _remind,
          onChanged: '${widget.customer['phone'] ?? ''}'.isEmpty ? null : _setRemind,
          title: const T('Vikumbusho vya kurudia dawa', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(_remind ? tr('Anakumbushwa dawa zikikaribia kuisha') : tr('Hakumbushwi'), style: const TextStyle(fontSize: 12)),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: dangerRed))),
        Expanded(
          child: _h == null && _error == null
              ? const Center(child: AfyaLoader())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
                  if (reminders.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('${tr('Vikumbusho vinavyosubiri')}: ${reminders.map((r) => '${r['product']} (${dayText('${r['due_on']}')})').join(', ')}',
                          style: const TextStyle(color: mutedText)),
                    ),
                  if (sales.isEmpty && _error == null) Padding(padding: const EdgeInsets.only(top: 24), child: Center(child: T('Bado hajanunua kitu tangu akubali.', style: const TextStyle(color: mutedText)))),
                  for (final s in sales) ...[
                    const Divider(height: 20),
                    Row(children: [
                      Text(dayText(parseDate(s['sold_at'])?.toLocal().toIso8601String()), style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${s['receipt_number']}', style: const TextStyle(color: mutedText, fontSize: 12), overflow: TextOverflow.ellipsis)),
                      Text(formatTsh(asInt(s['total'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    for (final l in (s['lines'] as List).cast<Map<String, dynamic>>())
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          Expanded(child: Text('${l['product']}')),
                          Text('${l['quantity']} ${l['unit'] ?? ''}', style: const TextStyle(color: mutedText)),
                        ]),
                      ),
                  ],
                ]),
        ),
      ]),
    );
  }
}
