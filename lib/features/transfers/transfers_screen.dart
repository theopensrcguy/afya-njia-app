import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/loader.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
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

  // ------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final partners = _list('partners');
    final canTransfer = d?['can_transfer'] == true;
    return Scaffold(
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Uhamisho wa hisa', style: TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: canTransfer && partners.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () async {
                final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(
                  builder: (_) => NewTransferScreen(session: widget.session, partners: partners, canApprove: _canApprove),
                ));
                if (sent == true && mounted) _load();
              },
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
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 96), children: [
                _codeCard(d),
                ..._linkRequests(),
                ..._section(tr('INAYOINGIA: THIBITISHA UMEPOKEA'), _list('transfers').where((t) => t['direction'] == 'in' && t['status'] == 'sent'), incoming: true),
                ..._section(tr('INASUBIRI IDHINI KUTOKA'), _list('transfers').where((t) => t['direction'] == 'out' && t['status'] == 'pending')),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 20, 4, 6),
                  child: T('HISTORIA YA UHAMISHO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: mutedText)),
                ),
                if (_list('transfers').isEmpty) const T('Bado hakuna uhamisho.', style: TextStyle(color: mutedText)),
                for (final t in _list('transfers')) _historyRow(t),
              ]),
            ),
    );
  }

  Widget _codeCard(Map<String, dynamic> d) {
    final linked = _list('links').where((l) => l['status'] == 'accepted').toList();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: softCard(radius: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const T('Namba ya duka lako', style: TextStyle(fontSize: 12, color: mutedText)),
        Row(children: [
          Text('${d['shop_code']}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3, color: brandGreen)),
          IconButton(
            tooltip: tr('Nakili'),
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: '${d['shop_code']}'));
              if (mounted) _toast(tr('Namba imenakiliwa.'));
            },
          ),
        ]),
        const T('Mpe duka jingine namba hii ili liunganishwe na lako. Ombi lake utaliona hapa.', style: TextStyle(fontSize: 12, color: mutedText)),
        const SizedBox(height: 10),
        const T('Maduka yaliyounganishwa', style: TextStyle(fontWeight: FontWeight.w800)),
        if (linked.isEmpty) const T('Bado hakuna. Unganisha kwa namba ya duka jingine.', style: TextStyle(color: mutedText)),
        for (final l in linked)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.storefront_outlined),
            title: Text('${(l['shop'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: (l['shop'] as Map)['location'] == null ? null : Text('${(l['shop'] as Map)['location']}'),
            trailing: !_canApprove
                ? null
                : TextButton(
                    onPressed: () async {
                      final ok = await confirmDialog(context,
                          title: tr('Tenganisha'),
                          message: tr('Tenganisha na :shop? Hamtaweza kuhamishiana hisa mpaka muunganishe tena.', {'shop': (l['shop'] as Map)['name']}),
                          confirm: tr('Tenganisha'),
                          danger: true);
                      if (ok == true) await _act(() => _api.delete('shop-links/${l['id']}'), tr('Yametenganishwa.'));
                    },
                    child: const T('Tenganisha'),
                  ),
          ),
        for (final l in _list('links').where((l) => l['status'] == 'pending' && l['asked_by_us'] == true))
          Text(tr(':shop: ombi lako linasubiri wakubali.', {'shop': (l['shop'] as Map)['name']}), style: const TextStyle(fontSize: 12, color: mutedText)),
        if (_canApprove)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(onPressed: _linkShop, icon: const Icon(Icons.link_rounded), label: const T('Unganisha na duka jingine')),
          ),
      ]),
    );
  }

  List<Widget> _linkRequests() {
    final asks = _list('links').where((l) => l['status'] == 'pending' && l['asked_by_us'] != true).toList();
    if (asks.isEmpty) return const [];
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: T('MAOMBI YA KUUNGANISHWA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: mutedText)),
      ),
      for (final l in asks)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: softCard(radius: 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${(l['shop'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(tr('ameomba :name', {'name': l['requested_by']}), style: const TextStyle(fontSize: 12, color: mutedText)),
            if (_canApprove)
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => _act(() => _api.post('shop-links/${l['id']}/decline', {}), tr('Ombi limekataliwa.')), child: const T('Kataa'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(onPressed: () => _act(() => _api.post('shop-links/${l['id']}/accept', {}), tr('Mmeunganishwa.')), child: const T('Kubali'))),
              ]),
          ]),
        ),
    ];
  }

  List<Widget> _section(String title, Iterable<Map<String, dynamic>> items, {bool incoming = false}) {
    final list = items.toList();
    if (list.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: mutedText)),
      ),
      for (final t in list)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: incoming ? const Color(0xFF2F5FA8) : warnAmber, width: 1.2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(incoming ? tr('Kutoka :shop', {'shop': (t['from'] as Map)['name']}) : tr('Kwenda :shop', {'shop': (t['to'] as Map)['name']}),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text(_summary(t)),
            if (t['note'] != null) Text('“${t['note']}”', style: const TextStyle(fontSize: 12, color: mutedText)),
            if (_costs && asInt(t['total_value']) > 0)
              Text(tr('Thamani (bei ya kununua): TSh :v', {'v': formatTsh(asInt(t['total_value'])).replaceAll('TSh ', '')}), style: const TextStyle(fontSize: 12, color: mutedText)),
            const SizedBox(height: 8),
            if (incoming && _canApprove)
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => _reject(t), style: OutlinedButton.styleFrom(foregroundColor: dangerRed), child: const T('Kataa (irudi)'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(onPressed: () => _receive(t), child: const T('Pokea'))),
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
                  Expanded(child: FilledButton(onPressed: () => _approve(t), child: const T('Idhinisha, tuma'))),
                ],
              ]),
          ]),
        ),
    ];
  }

  Widget _historyRow(Map<String, dynamic> t) {
    final (label, color) = switch ('${t['status']}') {
      'pending' => (tr('Inasubiri idhini'), warnAmber),
      'sent' => (tr('Imetumwa · inasubiri kupokelewa'), const Color(0xFF2F5FA8)),
      'received' => (tr('Imepokelewa'), brandGreen),
      'rejected' => (tr('Imekataliwa (imerudi)'), dangerRed),
      _ => (tr('Imeghairiwa'), mutedText),
    };
    final at = DateTime.tryParse('${t['sent_at'] ?? t['created_at'] ?? ''}');
    final out = t['direction'] == 'out';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(out ? Icons.north_east_rounded : Icons.south_west_rounded, color: out ? warnAmber : brandGreen),
      title: Text(out ? '→ ${(t['to'] as Map)['name']}' : '← ${(t['from'] as Map)['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${_summary(t)}\n${at == null ? '' : timeAgo(at)}', maxLines: 3, overflow: TextOverflow.ellipsis),
      isThreeLine: true,
      trailing: Text(label, textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w800)),
    );
  }
}
