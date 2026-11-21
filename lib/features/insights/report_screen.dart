import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import '../credit/madeni_screen.dart';
import '../orders/reorder_screen.dart';
import '../stock/product_stock_screen.dart';
import '../stock/stock_screen.dart';
import 'insight_parts.dart';

/// Ripoti ya biashara (v0.46, canvas 10): what an owner must know, in the
/// order to act on it. A verdict in one sentence with four vitals, the three
/// actions worth the most money (each opens where it's fixed), where the
/// profit goes, the 80/20 of products, profit by category, money resting on
/// shelves, losses and debts, customers, buying prices that moved.
/// GET insights/report?period=wiki|mwezi|miezi3|mwaka.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.session});

  final Session session;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  String _period = UiMemory.get('report.period', 'mwezi');
  int _tick = 0;
  Map<String, dynamic>? _last;

  void _open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  String _range(Map<String, dynamic> d) {
    String short(String iso) {
      final x = DateTime.tryParse(iso);
      if (x == null) return iso;
      final m = monthNames[x.month - 1];
      return '${x.day} ${m.length > 3 ? m.substring(0, 3) : m}';
    }

    return tr(':a – :b, dhidi ya :c – :d', {'a': short('${d['from']}'), 'b': short('${d['to']}'), 'c': short('${d['prev_from']}'), 'd': short('${d['prev_to']}')});
  }

  /// The report as a short WhatsApp message (to a partner, an accountant…),
  /// with the link to the full page when there is one.
  String _summary(Map<String, dynamic> d, String? link) {
    final v = ((d['vitals'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return <String>[
      '*${tr('Ripoti ya biashara')}* · ${_range(d)}',
      '${(d['verdict'] as Map?)?['text'] ?? ''}',
      '',
      for (final x in v)
        if (x['value'] != null) '• ${_vitalLabel('${x['key']}')}: ${_vitalValue(x)}',
      '',
      for (final a in ((d['actions'] as List?) ?? const []).cast<Map<String, dynamic>>()) '→ ${a['title']}',
      if (link != null) ...['', tr('Ripoti kamili (siku 3):'), link],
    ].join('\n');
  }

  /// Print or share (v0.46.1): the server makes a 3-day link to an A4 page of
  /// this report; the browser prints it or saves it as PDF, WhatsApp sends it.
  Future<void> _share() async {
    final d = _last;
    if (d == null) return;
    tick();
    String? link;
    try {
      link = '${(await widget.session.api.get('insights/report/link', query: {'period': _period}) as Map)['url']}';
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (!mounted) return;
    Future<void> go(Uri uri) async {
      Navigator.of(context).pop();
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('Haikufunguka kwenye simu hii.')));
      }
    }

    Widget item(IconData icon, String title, String sub, VoidCallback? onTap) => ListTile(
          enabled: onTap != null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: kDeep),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub, style: const TextStyle(fontSize: 12, color: kMuted)),
          onTap: onTap,
        );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const T('Chapisha au shiriki', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
            const SizedBox(height: 8),
            item(Icons.print_rounded, tr('Chapisha / Hifadhi PDF'), tr('Inafunguka kama ukurasa wa A4; bonyeza Chapisha'),
                link == null ? null : () => go(Uri.parse(link!))),
            item(Icons.chat_rounded, tr('Tuma kwa WhatsApp'), link == null ? tr('Muhtasari') : tr('Muhtasari na kiungo cha ripoti kamili'),
                () => go(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_summary(d, link))}'))),
            item(Icons.link_rounded, tr('Nakili kiungo'), tr('Kinafanya kazi kwa siku 3, bila kuingia'), link == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: link!));
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('Kiungo kimenakiliwa.')));
                  }),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(children: [
              Semantics(
                button: true,
                label: tr('Rudi'),
                excludeSemantics: true,
                child: Pressable(
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.chevron_left_rounded, color: kInk),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(child: T('Ripoti', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -.4))),
              IconButton(
                tooltip: tr('Chapisha au shiriki'),
                style: IconButton.styleFrom(backgroundColor: Colors.white, minimumSize: const Size(44, 44)),
                onPressed: _share,
                icon: const Icon(Icons.ios_share_rounded, color: kInk, size: 20),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SlidingSegments<String>(
              values: const ['wiki', 'mwezi', 'miezi3', 'mwaka'],
              labels: [tr('Wiki'), tr('Mwezi'), tr('Miezi 3'), tr('Mwaka')],
              selected: _period,
              height: 40,
              fontSize: 13,
              onChanged: (v) {
                setState(() => _period = v);
                UiMemory.set('report.period', v);
              },
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CachedJson(
              api: widget.session.api,
              path: 'insights/report',
              query: {'period': _period},
              refreshTick: _tick,
              skeleton: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [CardSkeleton(height: 260), SizedBox(height: 14), CardSkeleton(height: 200)]),
              ),
              builder: (context, d, _) {
                _last = d;
                return RefreshIndicator(
                  onRefresh: () async => setState(() => _tick++),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    children: staggered([
                      _verdict(d),
                      const SizedBox(height: 14),
                      if (((d['actions'] as List?) ?? const []).isNotEmpty) _actions(d),
                      if (d['waterfall'] is Map) ...[const SizedBox(height: 14), _waterfall(d['waterfall'] as Map<String, dynamic>)],
                      const SizedBox(height: 14),
                      _pareto(d['pareto'] as Map<String, dynamic>? ?? const {}),
                      if (((d['categories'] as List?) ?? const []).isNotEmpty) ...[const SizedBox(height: 14), _categories(d)],
                      if (d['stock'] is Map) ...[const SizedBox(height: 14), _stock(d['stock'] as Map<String, dynamic>)],
                      const SizedBox(height: 14),
                      _risks(d['risks'] as Map<String, dynamic>? ?? const {}),
                      const SizedBox(height: 14),
                      _customers(d['customers'] as Map<String, dynamic>? ?? const {}),
                      if (((d['prices'] as List?) ?? const []).isNotEmpty) ...[const SizedBox(height: 14), _prices(d)],
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------ verdict

  String _vitalLabel(String key) => switch (key) {
        'sales' => tr('Mauzo'),
        'net' => tr('Faida halisi'),
        'margin' => tr('Faida ghafi'),
        _ => tr('Hisa inatosha'),
      };

  String _vitalValue(Map<String, dynamic> v) => switch ('${v['key']}') {
        'margin' => '${v['value']}%',
        'cover' => tr('siku :n', {'n': v['value']}),
        _ => tshShort(asInt(v['value'])),
      };

  Widget _verdict(Map<String, dynamic> d) {
    final v = (d['verdict'] as Map?) ?? const {};
    final vitals = ((d['vitals'] as List?) ?? const []).cast<Map<String, dynamic>>().where((x) => x['value'] != null).toList();
    final good = v['good'] == true;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: kDeep, borderRadius: BorderRadius.circular(26)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: good ? const Color(0x293DDC97) : const Color(0x33F9B4A6), borderRadius: BorderRadius.circular(99)),
            child: Text('${v['badge'] ?? ''}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: good ? const Color(0xFF8FE6BE) : const Color(0xFFF9B4A6))),
          ),
          Text(_range(d), style: const TextStyle(fontSize: 12, color: Color(0xFFB7D3C9))),
        ]),
        const SizedBox(height: 12),
        Text('${v['text'] ?? ''}', style: const TextStyle(fontSize: 16.5, height: 1.45, fontWeight: FontWeight.w600, color: Colors.white)),
        const SizedBox(height: 14),
        // Pairs side by side, each pair as tall as its taller tile: they line up
        // and grow with the text (v0.48.1: a fixed height overflowed by 2 px with the delta badge).
        for (var i = 0; i < vitals.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _vitalTile(vitals[i])),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < vitals.length ? _vitalTile(vitals[i + 1]) : const SizedBox()),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _vitalTile(Map<String, dynamic> x) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .07), borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_vitalLabel('${x['key']}'), style: const TextStyle(fontSize: 11.5, color: Color(0xFFB7D3C9))),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: x['key'] == 'sales' || x['key'] == 'net'
                        ? CountUp(value: asInt(x['value']), format: tshShort, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))
                        : Text(_vitalValue(x), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  if (x['delta'] != null)
                    DeltaBadge(delta: x['delta'] as num?, onDark: true)
                  else if (x['diff'] != null)
                    Text(
                      '${(x['diff'] as num) >= 0 ? '↑' : '↓'} ${(x['diff'] as num).abs()} pt',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: (x['diff'] as num) >= 0 ? const Color(0xFF8FE6BE) : const Color(0xFFF9B4A6)),
                    )
                  else if (x['key'] == 'cover')
                    T('kwa mwendo huu', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFFB7D3C9))),
                ]),
              );

  // ------------------------------------------------------------ actions

  void _act(Map<String, dynamic> a) {
    final s = widget.session;
    switch ('${a['target']}') {
      case 'reorder':
        if (s.user!.can(Perm.prepareOrders)) _open(ReorderScreen(session: s));
      case 'debts':
        _open(MadeniScreen(session: s));
      case 'product':
        if (a['product_id'] != null) _open(ProductStockScreen(session: s, productId: asInt(a['product_id']), name: '${a['product_name'] ?? ''}'));
      case 'expiring':
        _open(StockScreen(session: s, initialFilter: 'muda'));
      default:
        _open(StockScreen(session: s));
    }
  }

  Widget _actions(Map<String, dynamic> d) {
    final list = ((d['actions'] as List?) ?? const []).cast<Map<String, dynamic>>();
    const tints = [(kBadSoft, kBad), (Color(0xFFFDF1E3), Color(0xFF7A4A12)), (Color(0xFFEAF0FD), Color(0xFF2F5FC4))];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(children: [
          Expanded(child: T('Mambo ya kufanya sasa', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kInk))),
          T('kwa uzito wa pesa', style: const TextStyle(fontSize: 12, color: kMuted)),
        ]),
      ),
      for (var i = 0; i < list.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _act(list[i]),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: tints[i % 3].$1, borderRadius: BorderRadius.circular(10)),
                    child: Center(child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w800, color: tints[i % 3].$2))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${list[i]['title']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.35, color: kInk)),
                      const SizedBox(height: 4),
                      Text('${list[i]['why']}', style: const TextStyle(fontSize: 12.5, height: 1.4, color: kMuted)),
                      const SizedBox(height: 4),
                      Text('${list[i]['cta']} →', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kPrimary)),
                    ]),
                  ),
                  if (list[i]['money'] != null) ...[
                    const SizedBox(width: 8),
                    Text(tshShort(asInt(list[i]['money'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
                  ],
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  // ------------------------------------------------------------ profit

  Widget _waterfall(Map<String, dynamic> w) {
    final sales = math.max(1, asInt(w['sales']));
    final steps = <(String, int, int, Color)>[
      (tr('Mauzo'), asInt(w['sales']), 0, kPrimary),
      (tr('Gharama ya dawa'), -asInt(w['cost']), asInt(w['gross']), const Color(0xFFF2A38F)),
      (tr('Faida ghafi'), asInt(w['gross']), 0, const Color(0xFF4D9F80)),
      (tr('Matumizi'), -asInt(w['expenses']), asInt(w['gross']) - asInt(w['expenses']), const Color(0xFFF2A38F)),
      (tr('Hasara'), -asInt(w['losses']), asInt(w['net']), const Color(0xFFF2A38F)),
      (tr('Faida halisi'), asInt(w['net']), 0, kDeep),
    ];
    final kept = w['kept_per_1000'];
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Faida inatoka wapi')),
        const SizedBox(height: 12),
        for (final (label, v, from, color) in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 108, child: Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF44564F)))),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final left = math.max(0, from) / sales * box.maxWidth;
                  final width = math.max(2.0, v.abs() / sales * box.maxWidth);
                  return SizedBox(
                    height: 18,
                    child: Stack(children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Motion.of(context, Motion.slow),
                        curve: Motion.curve,
                        builder: (_, t, _) => Positioned(
                          left: left,
                          width: math.min(width * t, box.maxWidth - left),
                          top: 0,
                          bottom: 0,
                          child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
                        ),
                      ),
                    ]),
                  );
                }),
              ),
              SizedBox(
                width: 72,
                child: Text('${v < 0 ? '− ' : ''}${shortMoney(v.abs())}',
                    textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: v < 0 ? kBad : kInk)),
              ),
            ]),
          ),
        if (kept != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(12)),
            child: Text(tr('Kati ya kila TSh 1,000 uliyouza, TSh :k ndiyo imebaki mfukoni baada ya dawa, matumizi na hasara.', {'k': kept}),
                style: const TextStyle(fontSize: 12.5, height: 1.45, color: Color(0xFF44564F))),
          ),
        ],
      ]),
    );
  }

  // ------------------------------------------------------------ 80/20

  Widget _pareto(Map<String, dynamic> p) {
    final top = ((p['top'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final products = asInt(p['products']);
    final n = asInt(p['top_count']);
    final pct = asInt(p['top_pct']);
    final low = asInt(p['low']);
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: CardTitle(tr('Kanuni ya 80/20'))),
          Text(tr('bidhaa :n', {'n': products}), style: const TextStyle(fontSize: 12, color: kMuted)),
        ]),
        const SizedBox(height: 12),
        if (n == 0)
          T('Bado hakuna mauzo kipindi hiki.', style: const TextStyle(color: kMuted))
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 24,
              child: Row(children: [
                Expanded(flex: math.max(1, pct), child: Container(color: kPrimary)),
                Expanded(flex: math.max(1, 100 - pct), child: Container(color: const Color(0xFFCDEFE0))),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(TextSpan(style: const TextStyle(fontSize: 12.5, color: Color(0xFF44564F)), children: [
            TextSpan(text: tr('Bidhaa :n (:p%)', {'n': n, 'p': pct}), style: const TextStyle(fontWeight: FontWeight.w800, color: kPrimary)),
            TextSpan(text: ' ${tr('zinaleta 80% ya mauzo.')}'),
          ])),
          const SizedBox(height: 6),
          Text(
            low > 0 ? tr('Hizi zisikose rafuni hata siku moja. :n kati yake ziko chini ya kiwango sasa.', {'n': low}) : tr('Hizi zisikose rafuni hata siku moja.'),
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: kMuted),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in top)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: t['low'] == true ? kBadSoft : kGoodSoft, borderRadius: BorderRadius.circular(99)),
                child: Text('${t['name']}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t['low'] == true ? kBad : const Color(0xFF0E5A44))),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _categories(Map<String, dynamic> d) {
    final list = ((d['categories'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final maxShare = list.fold<double>(1, (a, c) => math.max(a, (c['share'] as num).toDouble()));
    final best = list.where((c) => c['margin'] != null).fold<Map<String, dynamic>?>(null, (a, c) => a == null || asInt(c['margin']) > asInt(a['margin']) ? c : a);
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: CardTitle(tr('Faida kwa aina'))),
          T('mauzo · faida %', style: const TextStyle(fontSize: 12, color: kMuted)),
        ]),
        const SizedBox(height: 8),
        for (final c in list.take(7))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
                Text(tshShort(asInt(c['total'])), style: const TextStyle(fontSize: 12.5, color: kMuted)),
                if (c['margin'] != null)
                  SizedBox(
                    width: 46,
                    child: Text('${c['margin']}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: asInt(c['margin']) >= 35 ? kGood : (asInt(c['margin']) >= 20 ? kInk : kBad))),
                  ),
              ]),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, box) => Stack(children: [
                  Container(height: 8, decoration: BoxDecoration(color: const Color(0xFFEEF3F1), borderRadius: BorderRadius.circular(99))),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (c['share'] as num).toDouble() / maxShare),
                    duration: Motion.of(context, Motion.slow),
                    curve: Motion.curve,
                    builder: (_, v, _) =>
                        Container(width: math.max(4, box.maxWidth * v), height: 8, decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(99))),
                  ),
                ]),
              ),
            ]),
          ),
        if (best != null && list.length > 1) ...[
          const SizedBox(height: 6),
          Text(tr(':name ina faida kubwa zaidi (:m%): ipe nafasi karibu na kaunta.', {'name': best['name'], 'm': best['margin']}),
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: kMuted)),
        ],
      ]),
    );
  }

  // ------------------------------------------------------------ stock, risks, customers, prices

  Widget _stock(Map<String, dynamic> s) {
    final age = (s['age'] as Map?) ?? const {};
    const ages = [('30', '< siku 30', kPrimary), ('60', '30–60', Color(0xFF8FD3B6)), ('90', '60–90', Color(0xFFE39B2E)), ('older', '90+', Color(0xFFC2412D))];
    Widget tile(String label, String value, String note) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFFF5F8F7), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kMuted)),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kMuted)),
            ]),
          ),
        );
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Pesa iliyolala rafuni')),
        const SizedBox(height: 12),
        Row(children: [
          tile(tr('Thamani'), tshShort(asInt(s['value'])), tr('bei ya kununua')),
          tile(tr('Mzunguko'), s['turnover'] == null ? '—' : tr('mara :n', {'n': s['turnover']}), tr('kwa mwezi')),
          tile(tr('Inatosha'), s['cover_days'] == null ? '—' : tr('siku :n', {'n': s['cover_days']}), tr('kwa mwendo huu')),
        ]),
        const SizedBox(height: 14),
        T('Umri wa hisa (kwa thamani)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF44564F))),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 12,
            child: Row(children: [
              for (final (k, _, c) in ages)
                if (asInt((age[k] as Map?)?['pct']) > 0) Expanded(flex: asInt((age[k] as Map?)?['pct']), child: Container(color: c)),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 4, children: [
          for (final (k, label, c) in ages)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 4),
              Text('${tr(label)} ${asInt((age[k] as Map?)?['pct'])}%', style: const TextStyle(fontSize: 11.5, color: Color(0xFF44564F))),
            ]),
        ]),
      ]),
    );
  }

  Widget _risks(Map<String, dynamic> r) {
    final debts = (r['debts'] as Map?) ?? const {};
    final rows = <(String, String, String, String?, Color, VoidCallback?)>[
      if (r['expired'] != null)
        (tr('Zimeisha muda au kufutwa'), tr('hasara kwa bei ya kununua'), tshShort(asInt(r['expired'])),
            r['expired_pct'] == null ? null : tr(':p% ya mauzo', {'p': r['expired_pct']}), const Color(0xFF6E5A9E), null),
      if (r['adjustments'] != null)
        (tr('Pungufu kwenye hesabu ya hisa'), tr('marekebisho'), tshShort(asInt(r['adjustments'])), null, const Color(0xFFE39B2E), null),
      (tr('Madeni yanayodaiwa'), tr('wateja :n · :o zaidi ya siku 30', {'n': debts['count'] ?? 0, 'o': debts['overdue_count'] ?? 0}),
          tshShort(asInt(debts['total'])), asInt(debts['overdue_total']) > 0 ? tr(':a ya zamani', {'a': tshShort(asInt(debts['overdue_total']))}) : null,
          const Color(0xFFC2412D), () => _open(MadeniScreen(session: widget.session))),
    ];
    return InsightCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Hasara na madeni')),
        const SizedBox(height: 4),
        for (final (label, sub, value, note, color, onTap) in rows)
          InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF3F1)))),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(sub, style: const TextStyle(fontSize: 12, color: kMuted)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  if (note != null) Text(note, style: const TextStyle(fontSize: 11.5, color: kBad, fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _customers(Map<String, dynamic> c) {
    final ips = c['items_per_sale'];
    final ipsBefore = c['items_per_sale_before'];
    Widget tile(String label, String value, Widget? note) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFFF5F8F7), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kMuted)),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
              ?note,
            ]),
          ),
        );
    final diff = asInt(c['count_diff']);
    final fewer = ips != null && ipsBefore != null && (ips as num) < (ipsBefore as num);
    return InsightCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Wateja')),
        const SizedBox(height: 12),
        Row(children: [
          tile(tr('Mauzo'), '${c['count'] ?? 0}',
              Text('${diff >= 0 ? '↑' : '↓'} ${diff.abs()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: diff >= 0 ? kGood : kBad))),
          tile(tr('Wastani'), shortMoney(asInt(c['average'])), DeltaBadge(delta: c['average_delta'] as num?)),
          tile(tr('Wanarudi'), c['returning_pct'] == null ? '—' : '${c['returning_pct']}%', T('waliosajiliwa', style: const TextStyle(fontSize: 11, color: kMuted))),
        ]),
        if (fewer) ...[
          const SizedBox(height: 10),
          Text(tr('Wateja wananunua bidhaa :a kwa mauzo badala ya :b. Uliza "unahitaji na …?" kaunta.', {'a': ips, 'b': ipsBefore}),
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: kMuted)),
        ],
      ]),
    );
  }

  Widget _prices(Map<String, dynamic> d) {
    final list = ((d['prices'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return InsightCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: CardTitle(tr('Bei za kununua'))),
          T('mzigo wa mwisho dhidi ya kabla', style: const TextStyle(fontSize: 12, color: kMuted)),
        ]),
        const SizedBox(height: 6),
        for (final p in list)
          InkWell(
            onTap: () => _open(ProductStockScreen(session: widget.session, productId: asInt(p['product_id']), name: '${p['name']}')),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF3F1)))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    Text(
                      [
                        if (p['supplier'] != null) '${p['supplier']}',
                        '${p['pack']}${asInt(p['pack_size']) > 1 ? ' ${p['pack_size']}' : ''} ${formatTsh(asInt(p['pack_cost']))}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: kMuted),
                    ),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: (p['change'] as num) > 0 ? kBadSoft : kGoodSoft, borderRadius: BorderRadius.circular(99)),
                  child: Text('${(p['change'] as num) > 0 ? '↑' : '↓'} ${(p['change'] as num).abs().round()}%',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: (p['change'] as num) > 0 ? kBad : const Color(0xFF0E5A44))),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 4),
        if (list.any((p) => (p['change'] as num) > 0))
          T('Gharama ikipanda na bei ya kuuza isibadilike, faida inapungua: angalia bei za kuuza za hizi.',
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: kMuted)),
        const SizedBox(height: 8),
      ]),
    );
  }
}
