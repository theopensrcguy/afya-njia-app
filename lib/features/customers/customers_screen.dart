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
import '../../core/smooth.dart';
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

  // ------------------------------------------------------------ v0.47 look
  //
  // Layout A (agreed on the canvas): one white card with the counts on top
  // and today's reminders right under them in an amber band, then search,
  // filter chips and the customers as rows with coloured pills (as in the
  // ShopZen reference): reminders on / remind today / none / owes.

  String _filter = 'all'; // all | remind | today | debt | new
  bool _allDue = false;

  Set<int> get _dueIds => {for (final g in _groups('due')) asInt((g['customer'] as Map)['id'])};

  int? _daysSince(Map<String, dynamic> c) {
    final d = parseDate(c['last_sale_at']);
    return d == null ? null : DateTime.now().difference(d.toLocal()).inDays;
  }

  bool _isNew(Map<String, dynamic> c) {
    final d = parseDate(c['joined_at']);
    return d != null && DateTime.now().difference(d.toLocal()).inDays <= 30;
  }

  List<Map<String, dynamic>> get _shown {
    final q = _q.text.trim().toLowerCase();
    final digits = q.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0'), '');
    final due = _dueIds;
    return _customers.where((c) {
      final ok = switch (_filter) {
        'remind' => c['reminders_on'] == true,
        'today' => due.contains(asInt(c['id'])),
        'debt' => asInt(c['owes']) > 0,
        'new' => _isNew(c),
        _ => true,
      };
      return ok && (q.isEmpty || '${c['name']}'.toLowerCase().contains(q) || (digits.length >= 3 && '${c['phone'] ?? ''}'.contains(digits)));
    }).toList()
      ..sort((a, b) => (parseDate(b['last_sale_at']) ?? DateTime(2000)).compareTo(parseDate(a['last_sale_at']) ?? DateTime(2000)));
  }

  Future<void> _register() async {
    if (await registerCustomer(context, api: _api) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: T('Mteja amesajiliwa.')));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final due = _groups('due');
    final upcoming = _groups('upcoming');
    final sent = _groups('sent');
    final buyers = _customers.where((c) => asInt(c['sales']) > 0).length;
    final back = _customers.where((c) => asInt(c['sales']) > 1).length;
    final shown = _shown;
    final counts = {
      'all': _customers.length,
      'remind': _customers.where((c) => c['reminders_on'] == true).length,
      'today': due.length,
      'debt': _customers.where((c) => asInt(c['owes']) > 0).length,
      'new': _customers.where(_isNew).length,
    };
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F4),
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: AfyaLoader())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: dangerRed))))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                      children: [
                        Row(children: [
                          Pressable(
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Icons.chevron_left_rounded, color: _ink),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: T('Wateja', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _ink))),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: _deep, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                            onPressed: _register,
                            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                            label: const T('Sajili'),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        ...staggered([
                          _summary(due, buyers == 0 ? null : (back / buyers * 100).round()),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _q,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search_rounded),
                              hintText: tr('Tafuta jina au simu'),
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              for (final (k, label) in [
                                ('all', tr('Wote')),
                                ('remind', tr('Vikumbusho')),
                                if (counts['today']! > 0) ('today', tr('Kumbusha leo')),
                                if (counts['debt']! > 0) ('debt', tr('Wenye deni')),
                                ('new', tr('Wapya')),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Pressable(
                                    onTap: () {
                                      tick();
                                      setState(() => _filter = k);
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 160),
                                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                                      decoration: BoxDecoration(color: _filter == k ? _ink : Colors.white, borderRadius: BorderRadius.circular(99)),
                                      child: Text('$label ${counts[k]}',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _filter == k ? Colors.white : _ink)),
                                    ),
                                  ),
                                ),
                            ]),
                          ),
                          const SizedBox(height: 10),
                          if (_customers.isEmpty)
                            _emptyCard()
                          else if (shown.isEmpty)
                            Padding(padding: const EdgeInsets.all(28), child: T('Hakuna mteja hapa.', textAlign: TextAlign.center, style: const TextStyle(color: mutedText)))
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                              child: Column(children: [
                                for (var i = 0; i < shown.length; i++) _row(shown[i], last: i == shown.length - 1),
                              ]),
                            ),
                          if (upcoming.isNotEmpty || sent.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Theme(
                              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                              child: Container(
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                                child: ExpansionTile(
                                  shape: const RoundedRectangleBorder(),
                                  title: Text(tr('Vikumbusho vinavyokuja · :n', {'n': upcoming.length}), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                                  subtitle: sent.isEmpty ? null : Text(tr('Wamekumbushwa, hawajarudi · :n', {'n': sent.length}), style: const TextStyle(fontSize: 12, color: mutedText)),
                                  children: [
                                    for (final g in upcoming) _slim(g, tr('atakumbushwa :d', {'d': dayText('${g['due_on']}')})),
                                    for (final g in sent) _slim(g, tr('alikumbushwa :d', {'d': dayText(parseDate(g['sent_at'])?.toLocal().toIso8601String())})),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          const T('Anachonunua mtu duka la dawa ni taarifa ya afya yake. Zinahifadhiwa kwa aliyekubali tu, na mteja akisema ACHA, fungua jina lake uondoe ridhaa yake.',
                              style: TextStyle(color: mutedText, fontSize: 12)),
                        ]),
                      ],
                    ),
                  ),
      ),
    );
  }

  /// Counts on top; today's reminders in the amber band right under them.
  Widget _summary(List<Map<String, dynamic>> due, int? backPct) {
    Widget cell(String value, String label, {Color color = _ink, bool first = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(border: first ? null : const Border(left: BorderSide(color: Color(0xFFE3EAE7)))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: color == _ink ? mutedText : color)),
            ]),
          ),
        );
    final list = _allDue ? due : due.take(3).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              cell('${_customers.length}', tr('wateja'), first: true),
              cell(backPct == null ? '—' : '$backPct%', tr('wanarudi')),
              cell('${due.length}', tr('wa kukumbusha leo'), color: due.isEmpty ? _ink : _amber),
            ]),
          ),
          Container(
            decoration: const BoxDecoration(color: _amberSoft, border: Border(top: BorderSide(color: _amberLine))),
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: due.isEmpty
                ? Row(children: [
                    const Icon(Icons.check_circle_outline_rounded, size: 18, color: _amber),
                    const SizedBox(width: 8),
                    Expanded(child: T('Hakuna wa kukumbushwa leo.', style: const TextStyle(color: _amber, fontWeight: FontWeight.w600, fontSize: 13))),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(tr('WA KUKUMBUSHA LEO'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .5, color: _amber)),
                    const SizedBox(height: 4),
                    for (var i = 0; i < list.length; i++) _dueRow(list[i], top: i > 0),
                    if (due.length > 3)
                      TextButton(
                        style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero, foregroundColor: _amber),
                        onPressed: () => setState(() => _allDue = !_allDue),
                        child: Text(_allDue ? tr('Onyesha wachache') : tr('Ona wote :n →', {'n': due.length}), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    T('Ujumbe hautaji jina la dawa: simu inaweza kusomwa na mtu mwingine.', style: const TextStyle(fontSize: 11, color: _amber)),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _dueRow(Map<String, dynamic> g, {bool top = false}) {
    final c = (g['customer'] as Map).cast<String, dynamic>();
    final today = '${_board['today'] ?? ''}';
    final rs = (g['reminders'] as List).cast<Map<String, dynamic>>();
    final r0 = rs.isEmpty ? null : rs.first;
    final when = r0 == null
        ? ''
        : ('${r0['runs_out_on']}'.compareTo(today) < 0 ? tr('iliisha :d', {'d': dayText('${r0['runs_out_on']}')}) : tr('inaisha :d', {'d': dayText('${r0['runs_out_on']}')}));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(border: top ? const Border(top: BorderSide(color: _amberLine)) : null),
      child: Row(children: [
        _avatar('${c['name']}', 36),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => _open({...c, 'consent': true}),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
              Text([when, if (rs.length > 1) tr('dawa :n', {'n': rs.length})].where((e) => e.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 11.5, color: _amber)),
            ]),
          ),
        ),
        // Which medicines, and taking one off (it was bought elsewhere, the course ended).
        PopupMenuButton<Map<String, dynamic>>(
          tooltip: tr('Dawa za kikumbusho'),
          icon: const Icon(Icons.more_vert_rounded, size: 20, color: _amber),
          onSelected: _skip,
          itemBuilder: (_) => [
            for (final r in rs)
              PopupMenuItem(value: r, child: Text(tr('Ondoa: :p', {'p': r['product']}), maxLines: 2)),
          ],
        ),
        if (_board['sms'] == true)
          IconButton(tooltip: tr('Tuma SMS'), onPressed: () => _sms(g), icon: const Icon(Icons.sms_outlined, size: 20, color: _amber)),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3DDC97), foregroundColor: _deep, visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: () => _whatsapp(g),
          icon: const Icon(Icons.chat_rounded, size: 16),
          label: const T('Tuma', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> c, {bool last = false}) {
    final days = _daysSince(c);
    final due = _dueIds.contains(asInt(c['id']));
    final owes = asInt(c['owes']);
    final pills = <Widget>[
      if (due)
        _pill(tr('Kumbusha leo'), const Color(0xFFFFF1D9), _amber, const Color(0xFFF2C57C))
      else if (c['reminders_on'] == true)
        _pill(tr('Vikumbusho'), const Color(0xFFE3F4EA), const Color(0xFF0E5A44), const Color(0xFF9FD9BC))
      else
        _pill(tr('Bila vikumbusho'), const Color(0xFFF3F1EC), const Color(0xFF5F5E5A), const Color(0xFFD3D1C7)),
      if (owes > 0) _pill(tr('Deni :a', {'a': groupDigits(owes)}), const Color(0xFFFBE9E5), const Color(0xFFA8321F), const Color(0xFFF0B3A6)),
    ];
    return InkWell(
      onTap: () => _open(c),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFE3EAE7)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _avatar('${c['name']}', 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink, fontSize: 15)),
              Text([phoneText(c['phone']), tr('mara :n', {'n': c['sales'] ?? 0})].where((e) => e.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 12, color: mutedText)),
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 4, children: pills),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(groupDigits(asInt(c['spent'])), style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
            Text(days == null ? tr('bado') : (days == 0 ? tr('leo') : tr('siku :n', {'n': days})),
                style: TextStyle(fontSize: 12, color: (days ?? 0) > 60 ? _amber : mutedText)),
          ]),
        ]),
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg, Color line) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: Border.all(color: line, width: .6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ]),
      );

  Widget _emptyCard() => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          const Icon(Icons.groups_2_outlined, size: 44, color: mutedText),
          const SizedBox(height: 10),
          const T('Sajili mteja wako wa kwanza', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _ink)),
          const SizedBox(height: 4),
          const T('Kwa aliyekubali tu: kitufe cha Sajili hapo juu, au kwenye kikapu kwa "Weka mteja" kabla ya kukamilisha mauzo.',
              textAlign: TextAlign.center, style: TextStyle(color: mutedText, fontSize: 13)),
        ]),
      );

  Widget _slim(Map<String, dynamic> g, String when) => ListTile(
        dense: true,
        leading: _avatar('${g['customer']['name']}', 32),
        title: Text('${g['customer']['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text((g['reminders'] as List).map((r) => r['product']).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text(when, style: const TextStyle(color: mutedText, fontSize: 12)),
      );
}

const _ink = Color(0xFF14211D);
const _deep = Color(0xFF0E3B31);
const _amber = Color(0xFF7A4A12);
const _amberSoft = Color(0xFFFFF6E6);
const _amberLine = Color(0xFFF2D9A8);

/// Initials on a soft colour picked from the name.
Widget _avatar(String name, double size) {
  const colours = [Color(0xFFCDEFE0), Color(0xFFD9CCFF), Color(0xFFFFE0B8), Color(0xFFCFE3FF), Color(0xFFFBD5CF), Color(0xFFE4F79A)];
  final n = name.trim();
  final initials = n.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: colours[n.hashCode.abs() % colours.length], shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Text(initials.isEmpty ? '·' : initials, style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * .34, color: _ink)),
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
      if (mounted) {
        setState(() {
          _remind = !on;
          _error = e.message;
        });
      }
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
