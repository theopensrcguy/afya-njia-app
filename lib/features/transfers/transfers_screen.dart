import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/loader.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import 'new_transfer_screen.dart';

/// Uhamisho wa hisa: this shop's code, linked shops (and requests to link),
/// transfers to receive or approve, and the history. Approved on both sides:
/// A's owner sends, B confirms it arrived (or refuses: it goes back).
class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key, required this.session});

  final Session session;

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  ApiClient get _api => widget.session.api;
  bool get _canApprove => _data?['can_approve'] == true;
  bool get _costs => widget.session.user!.can(Perm.viewCosts);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.get('transfers') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _act(Future<dynamic> Function() call, String done) async {
    try {
      await call();
      if (!mounted) return;
      _toast(done);
      _load();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  List<Map<String, dynamic>> _list(String key) => (((_data ?? const {})[key] as List?) ?? const []).cast<Map<String, dynamic>>();

  Future<void> _linkShop() async {
    final code = await askText(context,
        title: tr('Unganisha na duka jingine'),
        message: tr('Andika namba ya duka hilo (wakupe kutoka ukurasa wao wa Uhamisho). Mmiliki wao atakubali, kisha mtaweza kuhamishiana hisa.'),
        label: tr('Namba ya duka'),
        hint: 'ABC123',
        required: true);
    if (code == null || code.trim().isEmpty) return;
    try {
      final r = await _api.post('shop-links', {'code': code.trim()}) as Map<String, dynamic>;
      if (!mounted) return;
      final shop = '${(r['shop'] as Map?)?['name'] ?? ''}';
      _toast(r['status'] == 'accepted'
          ? tr('Mmeunganishwa na :shop.', {'shop': shop})
          : tr('Ombi limetumwa kwa :shop. Wakikubali, mtaweza kuhamishiana hisa.', {'shop': shop}));
      _load();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  String _summary(Map<String, dynamic> t) {
    final byName = <String, (int, List<ProductUnit>)>{};
    for (final l in ((t['lines'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final units = ((l['units'] as List?) ?? const []).cast<Map<String, dynamic>>().map(ProductUnit.fromJson).toList();
      final prev = byName['${l['product']}'];
      byName['${l['product']}'] = ((prev?.$1 ?? 0) + asInt(l['quantity']), units);
    }
    return byName.entries.map((e) => '${e.key} ${describeStock(e.value.$1, e.value.$2)}').join(', ');
  }

  Future<void> _receive(Map<String, dynamic> t) async {
    Map<String, dynamic> full;
    try {
      full = await _api.get('transfers/${t['id']}') as Map<String, dynamic>;
    } on ApiException catch (e) {
      return _toast(e.message);
    }
    if (!mounted) return;
    final matches = (full['matches'] as Map?) ?? const {};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Pokea kutoka :shop', {'shop': (full['from'] as Map)['name']})),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const T('Hisa itaingia dukani kwako kwa batch na EXP zake, kwa bei ya kununua ya duka lililotuma. Bidhaa usiyonayo itaongezwa (bei za kuuza unaweza kubadilisha).',
                style: TextStyle(fontSize: 13, color: mutedText)),
            const SizedBox(height: 10),
            for (final l in ((full['lines'] as List?) ?? const []).cast<Map<String, dynamic>>())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${l['product']} · ${l['quantity']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    matches['${l['id']}'] is Map
                        ? tr('→ :name (yako)', {'name': (matches['${l['id']}'] as Map)['name']})
                        : tr('Itaongezwa kama bidhaa mpya'),
                    style: TextStyle(fontSize: 12, color: matches['${l['id']}'] is Map ? brandGreen : const Color(0xFF2F5FA8)),
                  ),
                ]),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const T('Ghairi')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const T('Thibitisha nimepokea')),
        ],
      ),
    );
    if (ok == true) await _act(() => _api.post('transfers/${t['id']}/receive', {}), tr('Imepokelewa. Hisa imeingia dukani.'));
  }

  Future<void> _reject(Map<String, dynamic> t) async {
    final note = await askText(context,
        title: tr('Kataa uhamisho'), message: tr('Hisa itarudi kwenye duka lililotuma.'), label: tr('Sababu (si lazima)'), danger: true, confirm: tr('Kataa'));
    if (note == null) return;
    await _act(() => _api.post('transfers/${t['id']}/reject', {'note': note.trim().isEmpty ? null : note.trim()}), tr('Umekataa. Hisa imerudi kwao.'));
  }

  Future<void> _approve(Map<String, dynamic> t) async {
    final ok = await confirmDialog(context,
        title: tr('Idhinisha, tuma'),
        message: tr('Idhinisha? Hisa itatoka dukani sasa hivi kwenda :shop.', {'shop': (t['to'] as Map)['name']}),
        confirm: tr('Idhinisha, tuma'));
    if (ok == true) {
      await _act(() => _api.post('transfers/${t['id']}/approve', {}), tr('Imetumwa. :shop watathibitisha wakipokea.', {'shop': (t['to'] as Map)['name']}));
    }
  }

  // ------------------------------------------------------------- layout (v0.48.2)

  int _tab = 0; // 0 = needs me, 1 = history

  Future<void> _newTransfer(List<Map<String, dynamic>> partners) async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => NewTransferScreen(session: widget.session, partners: partners, canApprove: _canApprove),
    ));
    if (sent == true && mounted) _load();
  }

  void _shareCode(String code) {
    final text = tr('Namba ya duka letu kwenye Afya Njia: :code. Iandike kwenye Uhamisho → Unganisha ili tuhamishiane hisa.', {'code': code});
    launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
  }

  Future<void> _shopSheet(Map<String, dynamic> l) async {
    final shop = (l['shop'] as Map).cast<String, dynamic>();
    final unlink = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListTile(
            leading: _avatar('${shop['name']}', 0),
            title: Text('${shop['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: shop['location'] == null ? null : Text('${shop['location']}'),
          ),
          if (_canApprove)
            ListTile(
              leading: const Icon(Icons.link_off_rounded, color: dangerRed),
              title: const T('Tenganisha', style: TextStyle(color: dangerRed)),
              onTap: () => Navigator.of(sheet).pop(true),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (unlink != true || !mounted) return;
    final ok = await confirmDialog(context,
        title: tr('Tenganisha'),
        message: tr('Tenganisha na :shop? Hamtaweza kuhamishiana hisa mpaka muunganishe tena.', {'shop': shop['name']}),
        confirm: tr('Tenganisha'),
        danger: true);
    if (ok == true) await _act(() => _api.delete('shop-links/${l['id']}'), tr('Yametenganishwa.'));
  }

  static const _avatarColors = [(Color(0xFFDDF3EA), Color(0xFF156B55)), (Color(0xFFEEEDFE), Color(0xFF3C3489)), (Color(0xFFFDF1DC), Color(0xFF8A5300)), (Color(0xFFE6F1FB), Color(0xFF185FA5))];

  Widget _avatar(String name, int i, {double size = 34}) {
    final (bg, fg) = _avatarColors[i % _avatarColors.length];
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty ? '?' : (words.length == 1 ? words.first.substring(0, 1) : '${words[0][0]}${words[1][0]}').toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Text(initials, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final partners = _list('partners');
    final canTransfer = d?['can_transfer'] == true;
    final transfers = _list('transfers');
    final incoming = transfers.where((t) => t['direction'] == 'in' && t['status'] == 'sent').toList();
    final pendingOut = transfers.where((t) => t['direction'] == 'out' && t['status'] == 'pending').toList();
    final asks = _list('links').where((l) => l['status'] == 'pending' && l['asked_by_us'] != true).toList();
    final waiting = incoming.length + pendingOut.length + asks.length;
    final code = '${d?['shop_code'] ?? ''}';

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: const T('Uhamisho wa hisa', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (code.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
                child: InkWell(
                  borderRadius: BorderRadius.circular(99),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (mounted) _toast(tr('Namba imenakiliwa.'));
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(code, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5, color: brandGreen)),
                      IconButton(
                        tooltip: tr('Shiriki namba'),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        onPressed: () => _shareCode(code),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: canTransfer && partners.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _newTransfer(partners),
              backgroundColor: brandGreen,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const T('Uhamisho mpya'),
            )
          : null,
      body: d == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const AfyaLoader())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 110), children: [
                _shopsRow(),
                const SizedBox(height: 12),
                _tabs(waiting),
                const SizedBox(height: 4),
                if (_tab == 0) ...[
                  if (waiting == 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
                      child: Column(children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 40, color: brandGreen),
                        const SizedBox(height: 8),
                        const T('Hakuna kinachokusubiri.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800)),
                        T(
                          partners.isEmpty ? 'Unganisha na duka jingine kwanza, kisha mtaweza kuhamishiana hisa.' : 'Hisa ikitumwa kwako, au uhamisho ukisubiri idhini, utaona hapa.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: mutedText),
                        ),
                      ]),
                    ),
                  ..._linkRequests(),
                  for (final t in incoming) _card(t, incoming: true),
                  for (final t in pendingOut) _card(t),
                ] else ...[
                  if (transfers.isEmpty) const Padding(padding: EdgeInsets.all(24), child: T('Bado hakuna uhamisho.', textAlign: TextAlign.center, style: TextStyle(color: mutedText))),
                  for (final t in transfers) _historyCard(t),
                ],
              ]),
            ),
    );
  }

  /// The shops this one is linked with (v0.48.4): a header that always shows
  /// "+ Unganisha duka", then the shops as chips, a round + first.
  Widget _shopsRow() {
    final linked = _list('links').where((l) => l['status'] == 'accepted').toList();
    final waitingOurs = _list('links').where((l) => l['status'] == 'pending' && l['asked_by_us'] == true).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(
            linked.isEmpty ? tr('Bado hujaunganisha duka') : tr('Maduka yaliyounganishwa · :n', {'n': linked.length}),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF14211D)),
          ),
        ),
        if (_canApprove)
          Pressable(
            onTap: _linkShop,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: brandGreen, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_link_rounded, size: 17, color: Colors.white),
                const SizedBox(width: 6),
                Text(tr('Unganisha duka'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 58,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          if (_canApprove)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Pressable(
                onTap: _linkShop,
                child: Container(
                  width: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F4EC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF8FD0B4), width: 1.2),
                  ),
                  child: const Icon(Icons.add_rounded, color: brandGreen, size: 26),
                ),
              ),
            ),
          for (final (i, l) in linked.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Pressable(
                onTap: () => _shopSheet(l),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 210),
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _avatar('${(l['shop'] as Map)['name']}', i),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${(l['shop'] as Map)['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        if ((l['shop'] as Map)['location'] != null)
                          Text('${(l['shop'] as Map)['location']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: mutedText)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          for (final l in waitingOurs)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: warnSoft, borderRadius: BorderRadius.circular(16)),
                child: Text(tr(':shop · inasubiri', {'shop': (l['shop'] as Map)['name']}), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: warnAmber, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _tabs(int waiting) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          for (final (i, label) in [(0, waiting > 0 ? tr('Zinanisubiri · :n', {'n': waiting}) : tr('Zinanisubiri')), (1, tr('Historia'))])
            Expanded(
              child: Pressable(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _tab == i ? inkColor : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _tab == i ? Colors.white : inkColor)),
                ),
              ),
            ),
        ]),
      );

  List<Widget> _linkRequests() {
    final asks = _list('links').where((l) => l['status'] == 'pending' && l['asked_by_us'] != true).toList();
    return [
      for (final l in asks)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF9FD9C2), width: 1.4)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.link_rounded, color: brandGreen, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(tr(':shop wanataka kuunganishwa', {'shop': (l['shop'] as Map)['name']}), style: const TextStyle(fontWeight: FontWeight.w800))),
            ]),
            Text(tr('ameomba :name', {'name': l['requested_by']}), style: const TextStyle(fontSize: 12, color: mutedText)),
            if (_canApprove) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => _act(() => _api.post('shop-links/${l['id']}/decline', {}), tr('Ombi limekataliwa.')), style: OutlinedButton.styleFrom(foregroundColor: dangerRed), child: const T('Kataa'))),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: FilledButton(onPressed: () => _act(() => _api.post('shop-links/${l['id']}/accept', {}), tr('Mmeunganishwa.')), child: const T('Kubali'))),
              ]),
            ],
          ]),
        ),
    ];
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
      );

  /// Needs me: stock sent to us (Pokea / Kataa), or ours waiting for approval.
  Widget _card(Map<String, dynamic> t, {bool incoming = false}) {
    final shop = incoming ? (t['from'] as Map)['name'] : (t['to'] as Map)['name'];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: incoming ? const Color(0xFF9FD9C2) : const Color(0xFFF1D7A6), width: 1.4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(incoming ? Icons.south_west_rounded : Icons.north_east_rounded, size: 18, color: incoming ? brandGreen : warnAmber),
          const SizedBox(width: 6),
          Expanded(
            child: Text(incoming ? tr('Kutoka :shop', {'shop': shop}) : tr('Kwenda :shop', {'shop': shop}),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 6),
          incoming ? _pill(tr('Pokea'), infoSoft, infoBlue) : _pill(tr('Inasubiri idhini'), warnSoft, warnAmber),
        ]),
        const SizedBox(height: 4),
        Text(_summary(t), maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: mutedText)),
        if (t['note'] != null) Text('“${t['note']}”', style: const TextStyle(fontSize: 12, color: mutedText, fontStyle: FontStyle.italic)),
        if (_costs && asInt(t['total_value']) > 0)
          Text(tr('Thamani (bei ya kununua): TSh :v', {'v': formatTsh(asInt(t['total_value'])).replaceAll('TSh ', '')}), style: const TextStyle(fontSize: 12, color: mutedText)),
        const SizedBox(height: 10),
        if (incoming && _canApprove)
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _reject(t), style: OutlinedButton.styleFrom(foregroundColor: dangerRed), child: const T('Kataa'))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: FilledButton(onPressed: () => _receive(t), child: const T('Pokea mzigo'))),
          ])
        else if (incoming)
          const T('Mmiliki au mwenye ruhusa atathibitisha.', style: TextStyle(fontSize: 12, color: mutedText))
        else
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _act(() => _api.post('transfers/${t['id']}/cancel', {}), tr('Uhamisho umeghairiwa.')),
                child: const T('Ghairi'),
              ),
            ),
            if (_canApprove) ...[
              const SizedBox(width: 8),
              Expanded(flex: 2, child: FilledButton(onPressed: () => _approve(t), child: const T('Idhinisha, tuma'))),
            ],
          ]),
      ]),
    );
  }

  Widget _historyCard(Map<String, dynamic> t) {
    final (label, bg, fg) = switch ('${t['status']}') {
      'pending' => (tr('Inasubiri idhini'), warnSoft, warnAmber),
      'sent' => (tr('Njiani'), infoSoft, infoBlue),
      'received' => (tr('Imepokelewa'), primarySoft, brandGreen),
      'rejected' => (tr('Imekataliwa · imerudi'), dangerSoft, dangerRed),
      _ => (tr('Imeghairiwa'), const Color(0xFFEFF3F1), mutedText),
    };
    final at = DateTime.tryParse('${t['sent_at'] ?? t['created_at'] ?? ''}');
    final out = t['direction'] == 'out';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: out ? warnSoft : primarySoft, borderRadius: BorderRadius.circular(11)),
          child: Icon(out ? Icons.north_east_rounded : Icons.south_west_rounded, size: 18, color: out ? warnAmber : brandGreen),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(out ? tr('Kwenda :shop', {'shop': (t['to'] as Map)['name']}) : tr('Kutoka :shop', {'shop': (t['from'] as Map)['name']}),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(_summary(t), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: mutedText)),
            const SizedBox(height: 6),
            Row(children: [
              Flexible(child: _pill(label, bg, fg)),
              if (at != null) ...[const SizedBox(width: 8), Text(timeAgo(at), style: const TextStyle(fontSize: 11.5, color: mutedText))],
            ]),
          ]),
        ),
      ]),
    );
  }
}
