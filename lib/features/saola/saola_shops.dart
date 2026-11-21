import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import '../support/support_screen.dart';
import 'saola_parts.dart';

/// Saola → Maduka in the app (v0.48.3): every shop, the ones needing a call
/// first; filter by state or by money, search by name or place.
class SaolaShopsScreen extends StatefulWidget {
  const SaolaShopsScreen({super.key, required this.session, this.filter = ''});

  final Session session;

  /// '' (zote) | fuatilia | hai | inaanza | inapoa | imelala | kulipa | imesimamishwa
  final String filter;

  @override
  State<SaolaShopsScreen> createState() => _SaolaShopsScreenState();
}

class _SaolaShopsScreenState extends State<SaolaShopsScreen> {
  List<Map<String, dynamic>>? _shops;
  String? _error;
  late String _filter = widget.filter;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.session.api.get('saola/shops') as Map<String, dynamic>;
      if (mounted) setState(() => (_shops = ((d['shops'] as List?) ?? const []).cast<Map<String, dynamic>>(), _error = null));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool _matches(Map<String, dynamic> s, String f) => switch (f) {
        '' => true,
        'fuatilia' => s['status'] == 'inapoa' || s['status'] == 'imelala',
        'kulipa' => needsPayment(s),
        _ => s['status'] == f,
      };

  static const _filters = [
    ('', 'Zote'),
    ('fuatilia', 'Ya kufuatilia'),
    ('hai', 'Hai'),
    ('inaanza', 'Inaanza'),
    ('inapoa', 'Inapoa'),
    ('imelala', 'Imelala'),
    ('kulipa', 'Malipo'),
    ('imesimamishwa', 'Imesimamishwa'),
  ];

  @override
  Widget build(BuildContext context) {
    final all = _shops ?? const <Map<String, dynamic>>[];
    final q = _q.text.trim().toLowerCase();
    final rows = [
      for (final s in all)
        if (_matches(s, _filter) && (q.isEmpty || '${s['name']} ${s['location'] ?? ''}'.toLowerCase().contains(q))) s,
    ];
    return Scaffold(
      backgroundColor: sBg,
      appBar: AppBar(backgroundColor: sBg, title: Text(tr('Maduka')), actions: [
        if (_shops != null) Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Text('${all.length}', style: const TextStyle(color: sMuted, fontWeight: FontWeight.w700)))),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: tr('Tafuta duka au mahali'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _q.text.isEmpty ? null : IconButton(onPressed: _q.clear, icon: const Icon(Icons.close_rounded)),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final (k, label) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChipX(
                    label: tr(label),
                    selected: _filter == k,
                    count: _shops == null ? null : all.where((s) => _matches(s, k)).length,
                    dot: k == '' || k == 'fuatilia' || k == 'kulipa' ? null : statusLook(k).$1,
                    onTap: () {
                      tick();
                      setState(() => _filter = k);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.base),
              child: _shops == null
                  ? ListView(key: const ValueKey('wait'), children: [
                      Padding(padding: const EdgeInsets.only(top: 60), child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))),
                    ])
                  : rows.isEmpty
                      ? ListView(key: ValueKey('empty$_filter'), children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(32, 60, 32, 0),
                            child: Column(children: [
                              const Icon(Icons.storefront_outlined, size: 40, color: Color(0xFFB8C4C0)),
                              const SizedBox(height: 10),
                              Text(tr('Hakuna duka hapa.'), style: const TextStyle(color: sMuted)),
                            ]),
                          ),
                        ])
                      : ListView.separated(
                          key: ValueKey('list$_filter|$q'),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => Appear(index: i.clamp(0, 8), child: _row(rows[i])),
                        ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final st = '${s['status']}';
    final (fg, soft, _) = statusLook(st);
    final b = (s['billing'] as Map?)?.cast<String, dynamic>() ?? const {};
    final (bf, bb) = billingLook('${b['status']}');
    final s7 = asInt(s['sales_7d']), p7 = asInt(s['sales_prev_7d']);
    final name = '${s['name']}';
    return Pressable(
      onTap: () async {
        await Navigator.of(context).push(riseRoute(SaolaShopScreen(session: widget.session, id: asInt(s['id']), name: name)));
        _load();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          Hero(
            tag: 'saola-shop-${s['id']}',
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(14)),
              child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: fg)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: sInk)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                pill('${s['status_label']}', fg, soft),
                if (needsPayment(s)) pill(billingLabel('${b['status']}'), bf, bb, icon: Icons.payments_outlined),
                Text(
                  s['last_sale_days'] == null
                      ? tr('haijauza bado')
                      : (asInt(s['last_sale_days']) == 0 ? tr('ameuza leo') : tr('mauzo ya mwisho siku :n', {'n': asInt(s['last_sale_days'])})),
                  style: const TextStyle(fontSize: 12, color: sMuted),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(groupDigits0(s7), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: sInk)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (s7 != p7) Icon(s7 > p7 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: s7 > p7 ? sGood : sBad),
              Text(tr('mauzo, siku 7'), style: const TextStyle(fontSize: 11, color: sMuted)),
            ]),
          ]),
        ]),
      ),
    );
  }
}

/// One shop: is it being used, who and what, setup, money with Saola, help asked.
class SaolaShopScreen extends StatefulWidget {
  const SaolaShopScreen({super.key, required this.session, required this.id, required this.name});

  final Session session;
  final int id;
  final String name;

  @override
  State<SaolaShopScreen> createState() => _SaolaShopScreenState();
}

class _SaolaShopScreenState extends State<SaolaShopScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _busy = false;
  String _chart = 'sales';

  ApiClient get _api => widget.session.api;
  String get _base => 'saola/shops/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.get(_base) as Map<String, dynamic>;
      if (mounted) setState(() => (_d = d, _error = null));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? sBad : null,
      content: Text(text),
    ));
  }

  Future<void> _run(Future<dynamic> Function() call) async {
    setState(() => _busy = true);
    try {
      final r = await call();
      if (r is Map && r['message'] != null) _toast('${r['message']}');
      await _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause(bool active) async {
    final ok = await confirmDialog(context,
        title: active ? tr('Simamisha duka?') : tr('Rudisha duka?'),
        message: active
            ? tr('Watu wote wa :shop watatolewa sasa hivi kwenye simu na vivinjari. Hakuna kinachofutwa; ukirudisha, kila kitu kiko pale pale.', {'shop': widget.name})
            : tr('Wataweza kuingia tena mara moja.'),
        confirm: active ? tr('Simamisha') : tr('Rudisha'),
        danger: active);
    if (ok == true) _run(() => _api.post('$_base/${active ? 'pause' : 'resume'}'));
  }

  Future<void> _ownerPin(String owner) async {
    final ok = await confirmDialog(context,
        title: tr('PIN mpya ya muda kwa :name?', {'name': owner}),
        message: tr('Fanya hivi tu ukiwa na uhakika ni yeye (muulize maswali ya duka lake). Atatolewa kwenye vifaa vyote na kupata PIN ya muda kwa SMS.'),
        confirm: tr('Tengeneza PIN'));
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final r = await _api.post('$_base/owner-pin') as Map<String, dynamic>;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(tr('PIN ya muda ya :name', {'name': '${r['name']}'})),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(color: const Color(0xFFE7F6EF), borderRadius: BorderRadius.circular(18)),
              child: Text('${r['pin']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, letterSpacing: 10, fontWeight: FontWeight.w800, color: sDeep)),
            ),
            const SizedBox(height: 12),
            Text(r['sms'] == true ? tr('SMS imetumwa. Inaonekana hapa mara hii moja tu.') : tr('SMS haikutumwa: mwambie kwa simu. Inaonekana hapa mara hii moja tu.'),
                style: const TextStyle(color: sMuted, fontSize: 13)),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.of(d).pop(), child: Text(tr('Nimemaliza')))],
        ),
      );
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveDevice(Map<String, dynamic> v) async {
    final code = await askText(context,
        title: tr('Ruhusu :device', {'device': '${v['name']}'}),
        message: tr('Mwombe mmiliki asome namba 6 zilizo kwenye skrini ya kifaa kipya.'),
        label: tr('Namba 6'),
        digitsOnly: true,
        required: true,
        confirm: tr('Ruhusu'));
    if (code == null || code.trim().isEmpty) return;
    _run(() => _api.post('$_base/devices/${v['id']}/approve', {'code': code.trim()}));
  }

  Future<void> _exempt(bool now) async {
    if (!now) {
      final reason = await askText(context,
          title: tr('Lisitozwe malipo?'),
          message: tr('Kwa duka la majaribio au mshirika. Halitakuwa la kusoma tu.'),
          label: tr('Sababu'),
          required: true,
          confirm: tr('Hifadhi'));
      if (reason == null || reason.trim().isEmpty) return;
      _run(() => _api.post('$_base/exempt', {'exempt': true, 'reason': reason.trim()}));
    } else {
      _run(() => _api.post('$_base/exempt', {'exempt': false}));
    }
  }

  Future<void> _void(Map<String, dynamic> p) async {
    final reason = await askText(context,
        title: tr('Batilisha malipo ya TSh :a?', {'a': groupDigits0(asInt(p['amount']))}),
        message: tr('"Amelipa mpaka" inarudi ilivyokuwa kabla.'),
        label: tr('Sababu'),
        required: true,
        danger: true,
        confirm: tr('Batilisha'));
    if (reason == null || reason.trim().length < 5) {
      if (reason != null) _toast(tr('Andika sababu (herufi 5 au zaidi).'), error: true);
      return;
    }
    _run(() => _api.post('$_base/payments/${p['id']}/void', {'reason': reason.trim()}));
  }

  Future<void> _pay(int monthly) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(api: _api, base: _base, monthly: monthly, shop: widget.name),
    );
    if (done == true) {
      _toast(tr('Malipo yamerekodiwa.'));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: sBg,
      body: d == null
          ? CustomScrollView(slivers: [
              SliverToBoxAdapter(child: _header(null)),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: _error == null ? const CircularProgressIndicator() : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center))),
              ),
            ])
          : AnimatedOpacity(
              opacity: _busy ? .6 : 1,
              duration: Motion.of(context, Motion.fast),
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: EdgeInsets.zero, children: [
                  _header(d),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: staggered(_body(d))),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _header(Map<String, dynamic>? d) {
    final s = (d?['shop'] as Map?)?.cast<String, dynamic>();
    final st = '${s?['status'] ?? ''}';
    final (_, _, dot) = statusLook(st);
    final b = (s?['billing'] as Map?)?.cast<String, dynamic>() ?? const {};
    final owner = (d?['owner'] as Map?)?.cast<String, dynamic>();
    final active = s?['is_active'] != false;
    final phone = owner?['phone'] as String?;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [sDeep, Color(0xFF12483C)]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
              const Spacer(),
              if (s != null) Text('${s['shop_code'] ?? ''}', style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(children: [
                Hero(
                  tag: 'saola-shop-${widget.id}',
                  child: Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
                    child: Text(widget.name.isEmpty ? '?' : widget.name.characters.first.toUpperCase(), style: const TextStyle(color: sMint, fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: Motion.of(context, Motion.base),
                      child: s == null
                          ? const SizedBox(height: 18)
                          : Wrap(key: ValueKey(st), spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Text('${s['status_label']}', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                              ]),
                              if ((s['location'] ?? '').toString().isNotEmpty)
                                Text('${s['location']}', style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                            ]),
                    ),
                  ]),
                ),
              ]),
            ),
            if (s != null) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.payments_outlined, color: sMint, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        b['message'] as String? ??
                            [billingLabel('${b['status']}'), if (b['ends_on'] != null) tr('mpaka :d', {'d': '${b['ends_on']}'})].join(' · '),
                        style: const TextStyle(color: Colors.white, fontSize: 12.5),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(children: [
                  _quick(Icons.call_outlined, tr('Piga'), phone == null ? null : () => launchUrl(Uri.parse('tel:${phone.replaceAll(' ', '')}'))),
                  _quick(Icons.password_rounded, tr('PIN mpya'), owner == null ? null : () => _ownerPin('${owner['name']}')),
                  _quick(active ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded, active ? tr('Simamisha') : tr('Rudisha'), () => _pause(active)),
                  _quick(Icons.add_card_rounded, tr('Malipo'), s['billing_exempt'] == true ? null : () => _pay(asInt(s['monthly_price']))),
                ]),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _quick(IconData icon, String label, VoidCallback? onTap) => Expanded(
        child: Opacity(
          opacity: onTap == null ? .4 : 1,
          child: Pressable(
            onTap: onTap == null
                ? null
                : () {
                    tick();
                    onTap();
                  },
            child: Column(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 21),
              ),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  List<Widget> _body(Map<String, dynamic> d) {
    final s = (d['shop'] as Map).cast<String, dynamic>();
    final days = ((d['days'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final setup = ((d['setup'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final people = ((d['people'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final devices = ((d['devices'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final payments = ((d['payments'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final tickets = ((d['tickets'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final waiting = devices.where((v) => v['owner_waiting'] == true).toList();
    final s7 = asInt(s['sales_7d']), p7 = asInt(s['sales_prev_7d']);
    final done = setup.where((x) => x['done'] == true).length;
    final req7 = asInt(s['requests_7d']), err7 = asInt(s['errors_7d']);

    return [
      for (final v in waiting)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFFF4DC), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Icon(Icons.phonelink_lock_outlined, color: sWarn),
              const SizedBox(width: 12),
              Expanded(
                child: Text(tr('Simu mpya ya mmiliki inasubiri: :device', {'device': '${v['name']}'}),
                    style: const TextStyle(color: sWarn, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              TextButton(onPressed: () => _approveDevice(v), child: Text(tr('Ruhusu'))),
            ]),
          ),
        ),
      // The numbers that say "is it being used".
      Row(children: [
        Expanded(child: _stat(tr('Mauzo, siku 7'), groupDigits0(s7), delta: s7 - p7)),
        const SizedBox(width: 10),
        Expanded(child: _stat(tr('Mauzo yote'), groupDigits0(asInt(s['sales_total'])))),
        const SizedBox(width: 10),
        Expanded(child: _stat(tr('Bidhaa'), groupDigits0(asInt(s['products'])))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _stat(tr('Wafanyakazi'), '${asInt(s['staff'])}')),
        const SizedBox(width: 10),
        Expanded(child: _stat(tr('Vifaa'), '${asInt(s['devices'])}', note: asInt(s['devices_waiting']) > 0 ? tr(':n vinasubiri', {'n': asInt(s['devices_waiting'])}) : null)),
        const SizedBox(width: 10),
        Expanded(child: _stat(tr('Hitilafu, siku 7'), '$err7', note: req7 == 0 ? null : '${(err7 * 100 / req7).toStringAsFixed(err7 * 100 / req7 < 1 ? 1 : 0)}%', bad: err7 > 0)),
      ]),
      const SizedBox(height: 14),
      sCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(tr('Siku 14'), style: const TextStyle(fontWeight: FontWeight.w800, color: sInk))),
            SizedBox(
              width: 190,
              child: SlidingSegments<String>(
                values: const ['sales', 'requests'],
                labels: [tr('Mauzo'), tr('Matumizi')],
                selected: _chart,
                height: 34,
                fontSize: 12.5,
                onChanged: (v) {
                  tick();
                  setState(() => _chart = v);
                },
              ),
            ),
          ]),
          const SizedBox(height: 14),
          DayBars(days: days, valueKey: _chart, errorKey: _chart == 'requests' ? 'errors' : null, color: _chart == 'sales' ? sGood : const Color(0xFF2F5FC4)),
          const SizedBox(height: 8),
          Text(
            s['last_seen_at'] == null
                ? tr('Hakuna aliyeingia bado.')
                : tr('Alionekana mwisho: :who, :when', {'who': '${s['last_seen_by'] ?? ''}', 'when': seenText(s['last_seen_at'] as String?)}),
            style: const TextStyle(fontSize: 12, color: sMuted),
          ),
        ]),
      ),
      sHeading(tr('Kuanza'), trailing: Text('$done/${setup.length}', style: const TextStyle(color: sMuted, fontWeight: FontWeight.w700))),
      sCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: setup.isEmpty ? 0 : done / setup.length),
              duration: Motion.of(context, Motion.slow),
              curve: Motion.curve,
              builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: const Color(0xFFEEF3F1), color: sGood),
            ),
          ),
          const SizedBox(height: 6),
          for (final x in setup)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(x['done'] == true ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: x['done'] == true ? sGood : const Color(0xFFB8C4C0)),
                const SizedBox(width: 10),
                Expanded(child: Text('${x['label']}', style: TextStyle(color: x['done'] == true ? sInk : sMuted, fontSize: 13.5))),
              ]),
            ),
        ]),
      ),
      sHeading(tr('Watu')),
      sCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          for (final (i, p) in people.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 64, color: sLine),
            ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: p['role'] == 'owner' ? const Color(0xFFE7F6EF) : const Color(0xFFEEF3F1),
                child: Text('${p['name']}'.isEmpty ? '?' : '${p['name']}'.characters.first.toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.w800, color: p['role'] == 'owner' ? sGood : sMuted)),
              ),
              title: Text('${p['name']}', style: TextStyle(fontWeight: FontWeight.w700, color: p['is_active'] == false ? sMuted : sInk, decoration: p['is_active'] == false ? TextDecoration.lineThrough : null)),
              subtitle: Text([p['role'] == 'owner' ? tr('Mmiliki') : tr('Mfanyakazi'), seenText(p['last_seen_at'] as String?)].join(' · ')),
            ),
          ],
        ]),
      ),
      if (devices.isNotEmpty) ...[
        sHeading(tr('Vifaa')),
        sCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            for (final (i, v) in devices.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 64, color: sLine),
              ListTile(
                dense: true,
                leading: Icon(v['mode'] == 'shared' ? Icons.point_of_sale_rounded : Icons.smartphone_rounded, color: v['status'] == 'approved' ? sGood : sWarn),
                title: Text('${v['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  v['status'] == 'approved' ? tr('Kimeruhusiwa') : (v['status'] == 'pending' ? tr('Kinasubiri') : tr('Kimeondolewa')),
                  if (v['last_user'] != null) '${v['last_user']}',
                  if (v['last_used_at'] != null) seenText(v['last_used_at'] as String?),
                ].join(' · ')),
                trailing: v['owner_waiting'] == true ? TextButton(onPressed: () => _approveDevice(v), child: Text(tr('Ruhusu'))) : null,
              ),
            ],
          ]),
        ),
      ],
      sHeading(tr('Malipo kwa Saola'), trailing: s['billing_exempt'] == true ? null : Text(tr('TSh :p / mwezi', {'p': groupDigits0(asInt(s['monthly_price']))}), style: const TextStyle(color: sMuted, fontSize: 12.5, fontWeight: FontWeight.w700))),
      sCard(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Halitozwi malipo'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(s['billing_exempt'] == true ? '${s['billing_exempt_reason'] ?? ''}' : tr('Duka la majaribio au mshirika')),
            value: s['billing_exempt'] == true,
            onChanged: (_) => _exempt(s['billing_exempt'] == true),
          ),
          if (payments.isEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(tr('Hakuna malipo yaliyorekodiwa bado.'), style: const TextStyle(color: sMuted)))
          else
            for (final p in payments)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(p['voided'] == true ? Icons.block_rounded : Icons.receipt_long_outlined, color: p['voided'] == true ? sMuted : sGood),
                title: Text('TSh ${groupDigits0(asInt(p['amount']))} · ${tr('miezi :n', {'n': asInt(p['months'])})}',
                    style: TextStyle(fontWeight: FontWeight.w700, decoration: p['voided'] == true ? TextDecoration.lineThrough : null)),
                subtitle: Text([
                  tr('mpaka :d', {'d': '${p['paid_until']}'}),
                  switch ('${p['method']}') { 'mobile' => tr('Simu'), 'bank' => tr('Benki'), _ => tr('Taslimu') },
                  if (p['reference'] != null) '${p['reference']}',
                ].join(' · ')),
                trailing: p['can_void'] == true ? IconButton(tooltip: tr('Batilisha'), onPressed: () => _void(p), icon: const Icon(Icons.undo_rounded, color: sMuted)) : null,
              ),
          if (s['billing_exempt'] != true)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 8, 10),
              child: OutlinedButton.icon(
                onPressed: () => _pay(asInt(s['monthly_price'])),
                style: OutlinedButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size.fromHeight(44)),
                icon: const Icon(Icons.add_rounded),
                label: Text(tr('Rekodi malipo')),
              ),
            ),
        ]),
      ),
      if (tickets.isNotEmpty) ...[
        sHeading(tr('Msaada wa duka hili')),
        for (final t in tickets) Padding(padding: const EdgeInsets.only(bottom: 8), child: ticketRow(context, widget.session, t, onBack: _load)),
      ],
      const SizedBox(height: 8),
      Text(tr('Namba tu: idadi ya mauzo, watu na vifaa. Pesa, wateja na hisa ya duka ni siri yao.'),
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: sMuted)),
    ];
  }

  Widget _stat(String label, String value, {int? delta, String? note, bool bad = false}) => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: bad ? sBad : sInk))),
            if (delta != null && delta != 0) ...[
              const SizedBox(width: 4),
              Icon(delta > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: delta > 0 ? sGood : sBad),
            ],
          ]),
          const SizedBox(height: 2),
          Text(note == null ? label : '$label · $note', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: sMuted, height: 1.25)),
        ]),
      );
}

/// One support ticket as a row (Msaada list, one shop's page).
Widget ticketRow(BuildContext context, Session session, Map<String, dynamic> t, {VoidCallback? onBack}) {
  final st = '${t['status']}';
  final urgent = st == 'open' && t['priority'] == 'urgent';
  final (fg, bg) = switch (st) {
    _ when urgent => (sBad, const Color(0xFFFBE9E5)),
    'open' => (sWarn, const Color(0xFFFFF4DC)),
    'answered' => (sGood, const Color(0xFFE7F6EF)),
    _ => (sMuted, const Color(0xFFEEF3F1)),
  };
  final at = DateTime.tryParse('${t['last_message_at']}');
  return Pressable(
    onTap: () async {
      await Navigator.of(context).push(riseRoute(SupportTicketScreen(session: session, id: asInt(t['id']), saola: true)));
      onBack?.call();
    },
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Icon(st == 'open' ? Icons.mark_chat_unread_outlined : Icons.chat_bubble_outline_rounded, color: fg, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (priorityPill(t) case final p?) ...[p, const SizedBox(width: 6)],
              Expanded(child: Text('${t['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: sInk))),
            ]),
            const SizedBox(height: 2),
            Text([if (t['category_label'] != null && t['category'] != 'other') '${t['category_label']}', if (t['pharmacy'] != null) '${t['pharmacy']}', if (t['opened_by'] != null) '${t['opened_by']}', if (at != null) timeAgo(at)].join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: sMuted)),
          ]),
        ),
        const SizedBox(width: 8),
        pill('${t['status_label']}', fg, bg),
      ]),
    ),
  );
}

/// "Rekodi malipo": months, amount (filled from the price), how, and the reference.
class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.api, required this.base, required this.monthly, required this.shop});

  final ApiClient api;
  final String base;
  final int monthly;
  final String shop;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  int _months = 1;
  String _method = 'mobile';
  late final _amount = TextEditingController(text: groupDigits0(widget.monthly));
  final _ref = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setMonths(int m) {
    tick();
    setState(() {
      _months = m;
      _amount.text = groupDigits0(widget.monthly * m);
    });
  }

  Future<void> _save() async {
    setState(() => (_busy = true, _error = null));
    try {
      await widget.api.post('${widget.base}/payments', {
        'amount': _amount.text.replaceAll(RegExp(r'\D'), ''),
        'months': _months,
        'method': _method,
        if (_ref.text.trim().isNotEmpty) 'reference': _ref.text.trim(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _box(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF4F8F6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: sLine, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 14),
              Text(tr('Rekodi malipo'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: sInk)),
              Text(widget.shop, style: const TextStyle(color: sMuted)),
              const SizedBox(height: 16),
              Text(tr('Miezi'), style: const TextStyle(fontWeight: FontWeight.w700, color: sInk)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final m in const [1, 3, 6, 12]) ChoiceChipX(label: tr('miezi :n', {'n': m}), selected: _months == m, onTap: () => _setMonths(m)),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: const [MoneyInput()],
                decoration: _box(tr('Kiasi (TSh)')),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              SlidingSegments<String>(
                values: const ['mobile', 'bank', 'cash'],
                labels: [tr('Simu'), tr('Benki'), tr('Taslimu')],
                selected: _method,
                onChanged: (v) {
                  tick();
                  setState(() => _method = v);
                },
              ),
              AnimatedSize(
                duration: Motion.of(context, Motion.base),
                curve: Motion.curve,
                child: _method == 'cash'
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: _ref,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-/ ]'))],
                          decoration: _box(tr('Namba ya muamala'), hint: 'QK12AB34CD'),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              TextField(controller: _note, decoration: _box(tr('Maelezo (si lazima)'))),
              AnimatedSize(
                duration: Motion.of(context, Motion.base),
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: sBad, fontSize: 13))),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2F8A6C), shape: const StadiumBorder(), minimumSize: const Size.fromHeight(50)),
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(tr('Hifadhi malipo'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
