import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'format.dart';
import 'i18n.dart';
import 'money.dart';
import 'range_picker.dart';
import 'smooth.dart';

/// Sharing with people who have no account (v0.47): a partner, an
/// accountant, an owner abroad. The server makes a signed link (3 days):
/// a printable page (Print / Save as PDF / Share in the browser) or an Excel
/// file. The sheets here choose what goes in it, then open, send or copy it.

const _ink = Color(0xFF14211D);
const _deep = Color(0xFF0E3B31);
const _muted = Color(0xFF5B6F69);

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ------------------------------------------------------------ sales

/// Mauzo → Shiriki: starts from the screen's period and payment filter.
Future<void> shareSales(BuildContext context, {required ApiClient api, required DateTime from, required DateTime to, String? method}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF5F8F7),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _SalesSheet(api: api, from: from, to: to, method: method),
  );
}

class _SalesSheet extends StatefulWidget {
  const _SalesSheet({required this.api, required this.from, required this.to, this.method});

  final ApiClient api;
  final DateTime from;
  final DateTime to;
  final String? method;

  @override
  State<_SalesSheet> createState() => _SalesSheetState();
}

class _SalesSheetState extends State<_SalesSheet> {
  late DateTime _from = widget.from;
  late DateTime _to = widget.to;
  late String _method = widget.method ?? '';
  String _seller = '';
  final _cats = <int>{};
  String _format = 'pdf';
  Map<String, dynamic>? _sum;
  int _ask = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Map<String, String> get _query => {
        'from': _iso(_from),
        'to': _iso(_to),
        if (_cats.isNotEmpty) 'cats': _cats.join(','),
        if (_method.isNotEmpty) 'method': _method,
        if (_seller.isNotEmpty) 'seller': _seller,
      };

  Future<void> _refresh() async {
    final n = ++_ask;
    try {
      final d = await widget.api.get('sales/export/summary', query: _query) as Map<String, dynamic>;
      if (mounted && n == _ask) setState(() => _sum = d);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _set(VoidCallback f) {
    tick();
    setState(f);
    _refresh();
  }

  String get _periodText {
    String d(DateTime x) => '${x.day} ${monthNames[x.month - 1]}';
    return _from == _to ? d(_from) : '${d(_from)} – ${d(_to)}';
  }

  Future<void> _go(String how) async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.get('sales/export/link', query: {..._query, 'format': _format}) as Map<String, dynamic>;
      final url = '${r['url']}';
      if (!mounted) return;
      final s = _sum;
      final summary = s == null
          ? ''
          : tr('Mauzo :p: :n, jumla :a.', {'p': _periodText, 'n': '${s['count']}', 'a': formatTsh(asInt(s['total']))});
      await _deliver(context, how, url, summary);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _sum;
    final cats = ((s?['categories'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final sellers = ((s?['sellers'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return _SheetFrame(
      icon: Icons.ios_share_rounded,
      title: tr('Shiriki mauzo'),
      subtitle: tr('Kwa mtu asiye na mfumo: mbia, mhasibu'),
      actions: _actions(_busy, _format, _go),
      children: [
        _label(tr('Kipindi')),
        _box(
          onTap: () async {
            final r = await pickDayOrRange(context, last: DateTime.now(), initial: DateTimeRange(start: _from, end: _to), maxDays: 366);
            if (r != null) _set(() => (_from = r.start, _to = r.end));
          },
          child: Row(children: [
            const Icon(Icons.calendar_month_outlined, size: 18, color: _deep),
            const SizedBox(width: 8),
            Expanded(child: Text(_periodText, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink))),
            const Icon(Icons.expand_more_rounded, color: _muted),
          ]),
        ),
        if (cats.isNotEmpty) ...[
          _label(tr('Aina (si lazima)')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in [...cats, {'id': 0, 'name': tr('Haijapangwa')}])
              _chip('${c['name']}', _cats.contains(asInt(c['id'])),
                  () => _set(() => _cats.contains(asInt(c['id'])) ? _cats.remove(asInt(c['id'])) : _cats.add(asInt(c['id'])))),
          ]),
        ],
        _label(tr('Malipo')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (k, label) in [('', tr('Zote')), ('cash', tr('Taslimu')), ('mobile', tr('Simu')), ('insurance', tr('Bima')), ('credit', tr('Deni'))])
            _chip(label, _method == k, () => _set(() => _method = k)),
        ]),
        if (sellers.length > 1) ...[
          _label(tr('Muuzaji')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(tr('Wote'), _seller.isEmpty, () => _set(() => _seller = '')),
            for (final u in sellers) _chip('${u['name']}', _seller == '${u['id']}', () => _set(() => _seller = '${u['id']}')),
          ]),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _deep, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Expanded(
              child: Text(s == null ? '…' : tr('mauzo :n', {'n': '${s['count']}'}), style: const TextStyle(color: Colors.white70)),
            ),
            Text(s == null ? '' : formatTsh(asInt(s['total'])), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ),
        if (_cats.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: T('Kwa aina zilizochaguliwa: jumla ni ya bidhaa hizo tu.', style: const TextStyle(fontSize: 11.5, color: _muted)),
          ),
        _formatPicker(_format, (f) => setState(() => _format = f)),
      ],
    );
  }
}

// ------------------------------------------------------------ stock

/// Hisa → Pakua: the stock as it stands, with the screen's filters.
/// [filter]: zote | chache | zimeisha | muda | zimeisha_muda.
Future<void> shareStock(BuildContext context,
    {required ApiClient api, String filter = 'zote', Set<int> cats = const {}, String q = '', List<String> describe = const []}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF5F8F7),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _StockSheet(api: api, filter: filter, cats: cats, q: q, describe: describe),
  );
}

class _StockSheet extends StatefulWidget {
  const _StockSheet({required this.api, required this.filter, required this.cats, required this.q, required this.describe});

  final ApiClient api;
  final String filter;
  final Set<int> cats;
  final String q;
  final List<String> describe;

  @override
  State<_StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends State<_StockSheet> {
  String _format = 'pdf';
  bool _all = false;
  bool _busy = false;

  bool get _filtered => widget.filter != 'zote' || widget.cats.isNotEmpty || widget.q.trim().isNotEmpty;

  Future<void> _go(String how) async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.get('stock/export-link', query: {
        'format': _format,
        if (!_all && widget.filter != 'zote') 'filter': widget.filter,
        if (!_all && widget.cats.isNotEmpty) 'cats': widget.cats.join(','),
        if (!_all && widget.q.trim().isNotEmpty) 'q': widget.q.trim(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      await _deliver(context, how, '${r['url']}', tr('Hisa iliyopo dukani.'));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      icon: Icons.inventory_2_outlined,
      title: tr('Pakua hisa'),
      subtitle: tr('Hisa iliyopo sasa, kwa aina zake'),
      actions: _actions(_busy, _format, _go),
      children: [
        if (_filtered) ...[
          _label(tr('Nini kiingie')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(tr('Kama orodha ilivyo sasa'), !_all, () => setState(() => _all = false)),
            _chip(tr('Hisa yote'), _all, () => setState(() => _all = true)),
          ]),
          if (!_all && widget.describe.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(widget.describe.join(' · '), style: const TextStyle(fontSize: 12.5, color: _muted)),
            ),
        ],
        _formatPicker(_format, (f) => setState(() => _format = f)),
      ],
    );
  }
}

// ------------------------------------------------------------ receipt

/// Any past sale's receipt: print it, save it as PDF, or send it.
Future<void> shareReceipt(BuildContext context, {required ApiClient api, required int saleId, required String how, String? phone}) async {
  try {
    final r = await api.get('sales/$saleId/receipt-link') as Map<String, dynamic>;
    if (!context.mounted) return;
    await _deliver(context, how, '${r['url']}', tr('Risiti yako:'), phone: phone, pop: false);
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

// ------------------------------------------------------------ staff (v0.48)

/// The staff list on A4 (owner): print / PDF, or send the link. No NIDA or personal details.
Future<void> shareStaffList(BuildContext context, {required ApiClient api, required String how}) async {
  try {
    final r = await api.get('staff/print-link') as Map<String, dynamic>;
    if (!context.mounted) return;
    await _deliver(context, how, '${r['url']}', tr('Orodha ya wafanyakazi:'), pop: false);
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

// ------------------------------------------------------------ shared parts

/// open: the page (print / PDF) or the Excel download; wa: WhatsApp with the
/// link; copy: the link to paste anywhere.
Future<void> _deliver(BuildContext context, String how, String url, String text, {String? phone, bool pop = true}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (pop) Navigator.of(context).pop();
  switch (how) {
    case 'copy':
      await Clipboard.setData(ClipboardData(text: url));
      messenger.showSnackBar(SnackBar(content: Text(tr('Kiungo kimenakiliwa. Kinafanya kazi kwa siku 3.'))));
    case 'wa':
      final to = (phone ?? '').replaceAll(RegExp(r'\D'), '');
      final ok = await launchUrl(Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent('$text\n$url')}'), mode: LaunchMode.externalApplication);
      if (!ok) messenger.showSnackBar(SnackBar(content: Text(tr('WhatsApp haikufunguka kwenye simu hii.'))));
    default:
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) messenger.showSnackBar(SnackBar(content: Text(tr('Haikufunguka kwenye simu hii.'))));
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.icon, required this.title, required this.subtitle, required this.children, required this.actions});

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .9),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: const Color(0xFFE3F4EA), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: const Color(0xFF0E5A44)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink)),
                  Text(subtitle, style: const TextStyle(fontSize: 12.5, color: _muted)),
                ]),
              ),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(20, 6, 20, 12), child: actions),
        ]),
      ),
    );
  }
}

Widget _label(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 0, 6),
      child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _muted)),
    );

Widget _box({required Widget child, VoidCallback? onTap}) => Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC9D6D1))),
          child: child,
        ),
      ),
    );

Widget _chip(String label, bool on, VoidCallback onTap) => Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(color: on ? _ink : Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: on ? _ink : const Color(0xFFDCE5E1))),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : _ink)),
      ),
    );

Widget _formatPicker(String value, ValueChanged<String> onChanged) {
  Widget card(String v, IconData icon, Color color, String title, String sub) => Expanded(
        child: Pressable(
          onTap: () {
            tick();
            onChanged(v);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: value == v ? _deep : const Color(0xFFDCE5E1), width: value == v ? 1.8 : 1),
            ),
            child: Column(children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
              Text(sub, style: const TextStyle(fontSize: 11.5, color: _muted)),
            ]),
          ),
        ),
      );
  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _label(tr('Muundo')),
    Row(children: [
      card('pdf', Icons.picture_as_pdf_outlined, const Color(0xFFA8321F), 'PDF', tr('ya kusoma, kuchapisha')),
      const SizedBox(width: 10),
      card('xlsx', Icons.table_chart_outlined, const Color(0xFF1F8A66), 'Excel', tr('ya kuchambua')),
    ]),
  ]);
}

Widget _actions(bool busy, String format, Future<void> Function(String how) go) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: _deep, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        onPressed: busy ? null : () => go('open'),
        icon: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(format == 'pdf' ? Icons.print_rounded : Icons.download_rounded),
        label: Text(format == 'pdf' ? tr('Fungua: chapisha au hifadhi PDF') : tr('Pakua Excel'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: busy ? null : () => go('wa'),
            icon: const Icon(Icons.chat_rounded, size: 18),
            label: const T('WhatsApp'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: busy ? null : () => go('copy'),
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const T('Nakili kiungo'),
          ),
        ),
      ]),
    ]);
