import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import '../insights/insight_parts.dart';
import '../orders/reorder_screen.dart';
import '../purchases/receive_screen.dart';
import 'supplier_form.dart';

/// "+255..." / "0712..." → "255712..." (for wa.me and tel:).
String? tzNumber(String? phone) {
  final d = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('0')) return '255${d.substring(1)}';
  if (d.length == 9) return '255$d';
  return d;
}

const _tints = [
  (Color(0xFFE7F6EF), Color(0xFF0E5A44), kPrimary),
  (Color(0xFFEAF0FD), Color(0xFF2F5FC4), Color(0xFF4D7FE0)),
  (Color(0xFFFDF1E3), Color(0xFF7A4A12), Color(0xFFE39B2E)),
  (Color(0xFFF0ECF7), Color(0xFF5B4790), Color(0xFF6E5A9E)),
  (Color(0xFFEEF3F1), Color(0xFF44564F), Color(0xFF8A9B95)),
];

String _initials(String name) =>
    name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

Future<void> _launch(BuildContext context, Uri uri) async {
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('Haikufunguka kwenye simu hii.')));
  }
}

Widget _backButton(BuildContext context) => Semantics(
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
    );

Widget _roundAction(IconData icon, String label, VoidCallback? onTap) => Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap ?? () {},
        child: Opacity(
          opacity: onTap == null ? .4 : 1,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(13)),
            child: Icon(icon, size: 19, color: kPrimary),
          ),
        ),
      ),
    );

/// Wasambazaji (v0.46, canvas 11): what was bought from whom in 90 days as
/// one bar, then each supplier as a card: contact, the 90-day spend, when the
/// last delivery came, how often they deliver, orders waiting, and call /
/// WhatsApp / Agiza in one tap. GET suppliers/overview.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key, required this.session});

  final Session session;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  String _sort = UiMemory.get('suppliers.sort', 'pesa');
  String _q = '';
  int _tick = 0;

  ApiClient get _api => widget.session.api;

  Future<void> _add() async {
    final s = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => SupplierFormScreen(api: _api)));
    if (s != null && mounted) setState(() => _tick++);
  }

  Future<void> _openOne(Map<String, dynamic> s) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupplierDetailScreen(session: widget.session, supplierId: asInt(s['id']))));
    if (mounted) setState(() => _tick++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: kInk,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, color: Color(0xFF3DDC97)),
        label: const T('Msambazaji mpya', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              _backButton(context),
              const SizedBox(width: 12),
              const T('Wasambazaji', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -.4)),
            ]),
          ),
          Expanded(
            child: CachedJson(
              api: _api,
              path: 'suppliers/overview',
              refreshTick: _tick,
              skeleton: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(children: [CardSkeleton(height: 150), SizedBox(height: 14), CardSkeleton(height: 160)]),
              ),
              builder: (context, d, _) => RefreshIndicator(
                onRefresh: () async => setState(() => _tick++),
                child: _body(d),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final all = ((d['suppliers'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final sum = (d['summary'] as Map?) ?? const {};
    final q = _q.trim().toLowerCase();
    final rows = all
        .where((s) => q.isEmpty || '${s['name']} ${s['contact_person'] ?? ''} ${s['location'] ?? ''}'.toLowerCase().contains(q))
        .toList();
    switch (_sort) {
      case 'jina':
        rows.sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
      case 'karibuni':
        rows.sort((a, b) => (a['last_delivery_days'] as int? ?? 99999).compareTo(b['last_delivery_days'] as int? ?? 99999));
    }
    // Same colour for a supplier everywhere on this page: by its place in the spend order.
    final colourOf = {for (var i = 0; i < all.length; i++) asInt(all[i]['id']): i % _tints.length};
    var n = 0;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      children: [
        if (all.isNotEmpty) Appear(index: n++, child: _summary(all, sum, colourOf)),
        const SizedBox(height: 14),
        TextField(
          onChanged: (v) => setState(() => _q = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: tr('Tafuta msambazaji'),
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (k, l) in const [('pesa', 'Kwa pesa'), ('karibuni', 'Mzigo wa karibuni'), ('jina', 'Jina')])
            ChoiceChipX(
              label: tr(l),
              selected: _sort == k,
              onTap: () {
                setState(() => _sort = k);
                UiMemory.set('suppliers.sort', k);
              },
            ),
        ]),
        const SizedBox(height: 12),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Column(children: [
              const Icon(Icons.storefront_outlined, size: 44, color: Color(0xFFB8C4C0)),
              const SizedBox(height: 10),
              T('Bado hakuna msambazaji. Ongeza wa kwanza.', style: const TextStyle(color: kMuted)),
            ]),
          ),
        for (final s in rows) Appear(index: n++, child: _card(s, colourOf[asInt(s['id'])] ?? 0)),
      ],
    );
  }

  Widget _summary(List<Map<String, dynamic>> all, Map sum, Map<int, int> colourOf) {
    final spend = sum['spend_90'];
    final withSpend = all.where((s) => asInt(s['spend_90']) > 0).toList();
    final total = withSpend.fold<int>(0, (a, s) => a + asInt(s['spend_90']));
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: kDeep, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: T('Umenunua siku 90', style: const TextStyle(fontSize: 13, color: Color(0xFFB7D3C9)))),
          Text(tr('wasambazaji :n · mizigo :d', {'n': sum['suppliers'] ?? all.length, 'd': sum['deliveries_90'] ?? 0}),
              style: const TextStyle(fontSize: 12, color: Color(0xFFB7D3C9))),
        ]),
        const SizedBox(height: 4),
        spend == null
            ? Text(tr('mizigo :n', {'n': sum['deliveries_90'] ?? 0}), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white))
            : CountUp(value: asInt(spend), format: formatTsh, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
        if (total > 0) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Row(children: [
                for (final s in withSpend)
                  Expanded(
                    flex: (asInt(s['spend_90']) * 1000 ~/ total).clamp(1, 1000),
                    child: Container(margin: const EdgeInsets.only(right: 2), color: _tints[colourOf[asInt(s['id'])] ?? 0].$3),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 14, runSpacing: 4, children: [
            for (final s in withSpend.take(5))
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: _tints[colourOf[asInt(s['id'])] ?? 0].$3, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('${'${s['name']}'.split(' ').first} ${(asInt(s['spend_90']) * 100 / total).round()}%',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFD6E7E0))),
              ]),
          ]),
        ],
      ]),
    );
  }

  Widget _card(Map<String, dynamic> s, int colour) {
    final (bg, fg, _) = _tints[colour];
    final phone = tzNumber(s['phone'] as String?);
    final wa = tzNumber((s['whatsapp_number'] ?? s['phone']) as String?);
    final contact = [s['contact_person'], s['phone']].where((x) => x != null && '$x'.isNotEmpty).join(' · ');
    final last = s['last_delivery_days'] as int?;
    final rhythm = s['rhythm_days'] as int?;
    final orders = asInt(s['open_orders']);
    final expected = s['expected_in_days'] as int?;
    Widget chip(String text, {Color bg = const Color(0xFFF2F6F4), Color fg = const Color(0xFF44564F), bool bold = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
          child: Text(text, style: TextStyle(fontSize: 12, color: fg, fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openOne(s),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
                  child: Center(child: Text(_initials('${s['name']}'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: fg))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${s['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: kInk)),
                    if (contact.isNotEmpty)
                      Text(contact, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: kMuted)),
                  ]),
                ),
                if (s['spend_90'] != null)
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(tshShort(asInt(s['spend_90'])), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kInk)),
                    T('siku 90', style: const TextStyle(fontSize: 11.5, color: kMuted)),
                  ]),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                chip(last == null ? tr('bado hakuna mzigo') : (last == 0 ? tr('mzigo wa mwisho: leo') : tr('mzigo wa mwisho: siku :n', {'n': last}))),
                if (rhythm != null) chip(tr('kila siku :n', {'n': rhythm})),
                if (orders > 0)
                  chip(orders == 1 ? tr('agizo 1 linasubiriwa') : tr('maagizo :n yanasubiriwa', {'n': orders}),
                      bg: const Color(0xFFEAF0FD), fg: const Color(0xFF2F5FC4), bold: true),
                if (expected != null && orders > 0)
                  chip(expected == 0 ? tr('linatarajiwa leo') : (expected == 1 ? tr('linatarajiwa kesho') : tr('linatarajiwa siku :n', {'n': expected})),
                      bg: const Color(0xFFFDF1E3), fg: const Color(0xFF7A4A12), bold: true),
              ]),
              const Divider(height: 24, color: Color(0xFFEEF3F1)),
              Row(children: [
                _roundAction(Icons.call_outlined, tr('Piga simu'), phone == null ? null : () => _launch(context, Uri.parse('tel:+$phone'))),
                const SizedBox(width: 8),
                _roundAction(Icons.chat_outlined, tr('WhatsApp'), wa == null ? null : () => _launch(context, Uri.parse('https://wa.me/$wa'))),
                const Spacer(),
                if (widget.session.user!.can(Perm.prepareOrders))
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReorderScreen(session: widget.session))),
                    style: FilledButton.styleFrom(
                      backgroundColor: kPrimary,
                      minimumSize: const Size(0, 42),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                    ),
                    icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
                    label: const T('Agiza', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One supplier (v0.46, canvas 12): call / WhatsApp / Agiza / Pokea, four
/// numbers (90-day spend and share, deliveries, how often, how fast an order
/// comes), waiting orders, what the shop buys there with the last price and
/// whether it moved, the deliveries, and the contacts. GET suppliers/{id}.
class SupplierDetailScreen extends StatefulWidget {
  const SupplierDetailScreen({super.key, required this.session, required this.supplierId});

  final Session session;
  final int supplierId;

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  String _tab = 'bidhaa';
  int _tick = 0;

  Future<void> _edit(Map<String, dynamic> s) async {
    final r = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => SupplierFormScreen(api: widget.session.api, initial: s)));
    if (r != null && mounted) setState(() => _tick++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        bottom: false,
        child: CachedJson(
          api: widget.session.api,
          path: 'suppliers/${widget.supplierId}',
          refreshTick: _tick,
          skeleton: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(children: [CardSkeleton(height: 120), SizedBox(height: 14), CardSkeleton(height: 200)]),
          ),
          builder: (context, s, _) => RefreshIndicator(
            onRefresh: () async => setState(() => _tick++),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: staggered([
                Row(children: [
                  _backButton(context),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _edit(s),
                    style: TextButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kInk, minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const T('Badilisha'),
                  ),
                ]),
                const SizedBox(height: 14),
                _head(s),
                const SizedBox(height: 14),
                _actions(s),
                const SizedBox(height: 14),
                _stats(s),
                for (final o in ((s['open_order_list'] as List?) ?? const []).cast<Map<String, dynamic>>()) ...[const SizedBox(height: 10), _order(o)],
                const SizedBox(height: 14),
                _tabs(s),
                const SizedBox(height: 14),
                _contacts(s),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _head(Map<String, dynamic> s) => Row(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: const Color(0xFFE7F6EF), borderRadius: BorderRadius.circular(20)),
          child: Center(child: Text(_initials('${s['name']}'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF0E5A44)))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s['name']}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: kInk)),
            if ([s['contact_person'], s['location']].any((x) => x != null && '$x'.isNotEmpty))
              Text([s['contact_person'], s['location']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 13, color: kMuted)),
            if ((s['tin'] ?? '').toString().isNotEmpty) Text('TIN ${s['tin']}', style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
        ),
      ]);

  Widget _actions(Map<String, dynamic> s) {
    final phone = tzNumber(s['phone'] as String?);
    final wa = tzNumber((s['whatsapp_number'] ?? s['phone']) as String?);
    final me = widget.session.user!;
    Widget qa(IconData icon, String label, VoidCallback? onTap, {bool primary = false}) => Expanded(
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: Pressable(
              onTap: onTap ?? () {},
              child: Opacity(
                opacity: onTap == null ? .45 : 1,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: Column(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: primary ? kPrimary : const Color(0xFFE7F6EF), borderRadius: BorderRadius.circular(14)),
                      child: Icon(icon, size: 19, color: primary ? Colors.white : kPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kInk)),
                  ]),
                ),
              ),
            ),
          ),
        );
    return Row(children: [
      qa(Icons.call_outlined, tr('Piga'), phone == null ? null : () => _launch(context, Uri.parse('tel:+$phone'))),
      qa(Icons.chat_outlined, tr('WhatsApp'), wa == null ? null : () => _launch(context, Uri.parse('https://wa.me/$wa'))),
      if (me.can(Perm.prepareOrders))
        qa(Icons.shopping_cart_checkout_rounded, tr('Agiza'),
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReorderScreen(session: widget.session))), primary: true),
      if (me.can(Perm.receive))
        qa(Icons.local_shipping_outlined, tr('Pokea'), () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiveScreen(session: widget.session, supplierId: widget.supplierId)));
          if (mounted) setState(() => _tick++);
        }),
    ]);
  }

  Widget _stats(Map<String, dynamic> s) {
    final st = (s['stats'] as Map?) ?? const {};
    final tiles = <(String, String, String)>[
      if (st['spend_90'] != null)
        (tr('Umenunua siku 90'), tshShort(asInt(st['spend_90'])), st['share_90'] == null ? '' : tr(':p% ya manunuzi yote', {'p': st['share_90']})),
      (tr('Mizigo'), '${st['deliveries'] ?? 0}', st['rhythm_days'] == null ? '' : tr('kila siku :n kwa wastani', {'n': st['rhythm_days']})),
      (tr('Agizo linafika baada ya'), st['lead_days'] == null ? '—' : tr('siku :n', {'n': st['lead_days']}), tr('tangu agizo kutumwa')),
      (tr('Bidhaa'), '${st['products'] ?? 0}', tr('unazonunua hapa')),
    ];
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 10) / 2;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (label, value, note) in tiles)
          SizedBox(
            width: w,
            child: InsightCard(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kMuted)),
                const SizedBox(height: 4),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kInk))),
                if (note.isNotEmpty) Text(note, maxLines: 2, style: const TextStyle(fontSize: 11.5, color: kMuted)),
              ]),
            ),
          ),
      ]);
    });
  }

  Widget _order(Map<String, dynamic> o) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFEAF0FD), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Icon(Icons.receipt_long_outlined, color: Color(0xFF2F5FC4)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Agizo #:id linasubiriwa', {'id': o['id']}), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF2F5FC4))),
              Text(
                tr('bidhaa :n · lilitumwa :when', {
                  'n': o['lines'],
                  'when': o['days'] == null ? '—' : (o['days'] == 0 ? tr('leo') : tr('siku :n zilizopita', {'n': o['days']})),
                }),
                style: const TextStyle(fontSize: 12, color: Color(0xFF2F5FC4)),
              ),
            ]),
          ),
        ]),
      );

  Widget _tabs(Map<String, dynamic> s) {
    final products = ((s['products'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final history = ((s['history'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return InsightCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SlidingSegments<String>(
          values: const ['bidhaa', 'mizigo'],
          labels: [tr('Bidhaa na bei'), tr('Mizigo')],
          selected: _tab,
          height: 38,
          fontSize: 13,
          onChanged: (v) => setState(() => _tab = v),
        ),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.curve,
          alignment: Alignment.topCenter,
          child: _tab == 'bidhaa'
              ? Column(children: [
                  if (products.isEmpty) _empty(tr('Bado hakuna bidhaa kutoka kwa msambazaji huyu.')),
                  for (final p in products) _productRow(p),
                ])
              : Column(children: [
                  if (history.isEmpty) _empty(tr('Bado hakuna mzigo.')),
                  for (final h in history) _deliveryRow(h),
                ]),
        ),
      ]),
    );
  }

  Widget _empty(String text) => Padding(padding: const EdgeInsets.all(20), child: Text(text, style: const TextStyle(color: kMuted)));

  Widget _productRow(Map<String, dynamic> p) {
    final change = p['change'] as num?;
    final at = DateTime.tryParse('${p['last_at']}');
    final packText = asInt(p['pack_size']) > 1 ? tr(':pack ya :n', {'pack': '${p['pack']}', 'n': p['pack_size']}) : '${p['pack']}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF3F1)))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
            Text('$packText · ${at == null ? '' : swahiliDate(at)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (p['pack_cost'] != null) Text(formatTsh(asInt(p['pack_cost'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
          if (change != null)
            Text(
              change == 0 ? tr('= sawa') : '${change > 0 ? '↑' : '↓'} ${change.abs().round()}%',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: change > 0 ? kBad : (change < 0 ? kGood : kMuted)),
            ),
        ]),
      ]),
    );
  }

  Widget _deliveryRow(Map<String, dynamic> h) {
    final at = DateTime.tryParse('${h['received_at']}')?.toLocal();
    final rejected = h['status'] == 'rejected';
    final pending = h['status'] == 'pending';
    final sub = [
      tr('bidhaa :n', {'n': h['lines']}),
      if ((h['by'] ?? '').toString().isNotEmpty) '${h['by']}',
      if (rejected && h['rejected_reason'] != null) '${h['rejected_reason']}',
      if (pending) tr('inasubiri uthibitisho'),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF3F1)))),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: rejected ? kBadSoft : kBg, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(at == null ? '—' : '${at.day}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: rejected ? kBad : kInk)),
            if (at != null) Text(monthNames[at.month - 1].substring(0, 3), style: const TextStyle(fontSize: 10, color: kMuted)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rejected ? tr('Ilikataliwa') : ((h['invoice_number'] ?? '').toString().isEmpty ? tr('Bila namba ya ankara') : tr('Ankara :n', {'n': h['invoice_number']})),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: rejected ? kBad : kInk)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
        ),
        if (h['total_cost'] != null && !rejected) Text(formatTsh(asInt(h['total_cost'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kInk)),
      ]),
    );
  }

  Widget _contacts(Map<String, dynamic> s) {
    final rows = <(IconData, String, String, Uri?)>[
      if ((s['phone'] ?? '').toString().isNotEmpty)
        (Icons.call_outlined, tr('Simu'), '${s['phone']}', tzNumber(s['phone'] as String?) == null ? null : Uri.parse('tel:+${tzNumber(s['phone'] as String?)}')),
      if ((s['whatsapp_number'] ?? s['whatsapp'] ?? '').toString().isNotEmpty)
        (Icons.chat_outlined, tr('WhatsApp (maagizo yanaenda hapa)'), '${s['whatsapp'] ?? s['whatsapp_number']}',
            Uri.parse('https://wa.me/${tzNumber((s['whatsapp_number'] ?? s['whatsapp']) as String?)}')),
      if ((s['email'] ?? '').toString().isNotEmpty) (Icons.mail_outline, tr('Barua pepe'), '${s['email']}', Uri.parse('mailto:${s['email']}')),
      if ((s['location'] ?? '').toString().isNotEmpty) (Icons.place_outlined, tr('Mahali'), '${s['location']}', null),
      if ((s['notes'] ?? '').toString().isNotEmpty) (Icons.notes_rounded, tr('Maelezo'), '${s['notes']}', null),
    ];
    if (rows.isEmpty) return const SizedBox();
    return InsightCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardTitle(tr('Mawasiliano')),
        const SizedBox(height: 4),
        for (final (icon, label, value, uri) in rows)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: uri == null ? null : () => _launch(context, uri),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: kBg, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 17, color: kPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: const TextStyle(fontSize: 11.5, color: kMuted)),
                    Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk)),
                  ]),
                ),
                if (uri != null) const Icon(Icons.open_in_new_rounded, size: 16, color: kMuted),
              ]),
            ),
          ),
      ]),
    );
  }
}
