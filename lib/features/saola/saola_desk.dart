import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import 'saola_parts.dart';
import 'saola_shops.dart';

/// Maombi ya maduka mapya, in the app (v0.48.3): check the licence, call,
/// then open the shop on the owner's number or say no with a reason.
class SaolaRequestsScreen extends StatefulWidget {
  const SaolaRequestsScreen({super.key, required this.session});

  final Session session;

  @override
  State<SaolaRequestsScreen> createState() => _SaolaRequestsScreenState();
}

class _SaolaRequestsScreenState extends State<SaolaRequestsScreen> {
  List<Map<String, dynamic>>? _waiting;
  List<Map<String, dynamic>> _done = [];
  String? _error;
  final Set<int> _busy = {};

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.get('saola/shop-requests') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _waiting = ((d['waiting'] as List?) ?? const []).cast<Map<String, dynamic>>();
          _done = ((d['done'] as List?) ?? const []).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _decide(Map<String, dynamic> r, bool yes) async {
    String? reason;
    if (yes) {
      final ok = await confirmDialog(context,
          title: tr('Fungua ":shop"?', {'shop': '${r['name']}'}),
          message: tr('Litafunguliwa kwenye namba ya :name, na majaribio ya bure. Atapata SMS.', {'name': '${r['requester'] ?? ''}'}),
          confirm: tr('Kubali na fungua'));
      if (ok != true) return;
    } else {
      reason = await askText(context,
          title: tr('Kataa ":shop"?', {'shop': '${r['name']}'}),
          message: tr('Mwombaji atapata sababu hii kwa SMS.'),
          label: tr('Sababu'),
          required: true,
          danger: true,
          confirm: tr('Kataa'));
      if (reason == null || reason.trim().length < 3) return;
    }
    final id = asInt(r['id']);
    setState(() => _busy.add(id));
    try {
      final res = await _api.post('saola/shop-requests/$id/${yes ? 'approve' : 'reject'}', {if (reason != null) 'reason': reason.trim()}) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text('${res['message']}')));
      await _load();
      if (yes && res['shop_id'] != null && mounted) {
        Navigator.of(context).push(riseRoute(SaolaShopScreen(session: widget.session, id: asInt(res['shop_id']), name: '${r['name']}')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, backgroundColor: sBad, content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _waiting;
    return Scaffold(
      backgroundColor: sBg,
      appBar: AppBar(backgroundColor: sBg, title: Text(tr('Maombi ya maduka'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: waiting == null
            ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 60), child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!)))])
            : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 30), children: staggered([
                if (waiting.isEmpty)
                  sCard(
                    child: Row(children: [
                      const Icon(Icons.inbox_outlined, color: sGood),
                      const SizedBox(width: 12),
                      Expanded(child: Text(tr('Hakuna ombi linalosubiri.'), style: const TextStyle(color: sMuted))),
                    ]),
                  )
                else
                  for (final r in waiting) Padding(padding: const EdgeInsets.only(bottom: 10), child: _waitingCard(r)),
                if (_done.isNotEmpty) ...[
                  sHeading(tr('Yaliyojibiwa')),
                  sCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(children: [
                      for (final (i, r) in _done.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16, color: sLine),
                        ListTile(
                          dense: true,
                          title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text([
                            '${r['requester'] ?? ''}',
                            if (r['decision_note'] != null) '${r['decision_note']}',
                          ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: switch ('${r['status']}') {
                            'approved' => pill(tr('Limefunguliwa'), sGood, const Color(0xFFE7F6EF)),
                            'rejected' => pill(tr('Limekataliwa'), sBad, const Color(0xFFFBE9E5)),
                            _ => pill(tr('Limeghairiwa'), sMuted, const Color(0xFFEEF3F1)),
                          },
                          onTap: r['opened_shop_id'] == null
                              ? null
                              : () => Navigator.of(context).push(riseRoute(SaolaShopScreen(session: widget.session, id: asInt(r['opened_shop_id']), name: '${r['name']}'))),
                        ),
                      ],
                    ]),
                  ),
                ],
              ])),
      ),
    );
  }

  Widget _waitingCard(Map<String, dynamic> r) {
    final id = asInt(r['id']);
    final busy = _busy.contains(id);
    final phone = r['phone'] as String?;
    final at = DateTime.tryParse('${r['created_at']}');
    Widget line(IconData icon, String text, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Icon(icon, size: 17, color: sMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, color: sInk))),
            ?trailing,
          ]),
        );
    return AnimatedOpacity(
      opacity: busy ? .55 : 1,
      duration: Motion.of(context, Motion.fast),
      child: sCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: const Color(0xFFEAF0FD), borderRadius: BorderRadius.circular(13)),
              child: const Icon(Icons.add_business_outlined, color: Color(0xFF2F5FC4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${r['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: sInk)),
                if (at != null) Text(timeAgo(at), style: const TextStyle(fontSize: 12, color: sMuted)),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          line(Icons.person_outline_rounded, [
            '${r['requester'] ?? ''}',
            if (r['from_shop'] != null) tr('kutoka :shop', {'shop': '${r['from_shop']}'}),
          ].join(' · '),
              trailing: phone == null
                  ? null
                  : IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: tr('Piga'),
                      onPressed: () => launchUrl(Uri.parse('tel:${phone.replaceAll(' ', '')}')),
                      icon: const Icon(Icons.call_outlined, color: sGood, size: 20),
                    )),
          if ((r['location'] ?? '').toString().isNotEmpty) line(Icons.place_outlined, '${r['location']}'),
          line(Icons.verified_outlined, tr('Leseni: :n', {'n': '${r['licence_number']}'}),
              trailing: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('Nakili'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${r['licence_number']}'));
                  tick();
                },
                icon: const Icon(Icons.copy_rounded, size: 18, color: sMuted),
              )),
          if ((r['note'] ?? '').toString().isNotEmpty) line(Icons.notes_rounded, '${r['note']}'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => _decide(r, false),
                style: OutlinedButton.styleFrom(foregroundColor: sBad, shape: const StadiumBorder(), minimumSize: const Size.fromHeight(44), side: const BorderSide(color: Color(0xFFF0C9C1))),
                child: Text(tr('Kataa')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: busy ? null : () => _decide(r, true),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2F8A6C), shape: const StadiumBorder(), minimumSize: const Size.fromHeight(44)),
                child: Text(tr('Kubali na fungua')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Msaada for Saola, in the app (v0.48.3): every shop's tickets, the ones
/// waiting longest first. A ticket opens in the ordinary chat (as Saola).
class SaolaTicketsScreen extends StatefulWidget {
  const SaolaTicketsScreen({super.key, required this.session});

  final Session session;

  @override
  State<SaolaTicketsScreen> createState() => _SaolaTicketsScreenState();
}

class _SaolaTicketsScreenState extends State<SaolaTicketsScreen> {
  String _status = 'open';
  List<Map<String, dynamic>>? _tickets;
  Map<String, dynamic> _counts = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.session.api.get('saola/tickets', query: {'status': _status}) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _tickets = ((d['tickets'] as List?) ?? const []).cast<Map<String, dynamic>>();
          _counts = d['counts'] is Map ? (d['counts'] as Map).cast<String, dynamic>() : {};
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _tickets;
    String label(String k, String text) => asInt(_counts[k]) > 0 ? '$text ${asInt(_counts[k])}' : text;
    return Scaffold(
      backgroundColor: sBg,
      appBar: AppBar(backgroundColor: sBg, title: Text(tr('Msaada'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: SlidingSegments<String>(
            values: const ['open', 'answered', 'closed'],
            labels: [label('open', tr('Inasubiri')), label('answered', tr('Wamejibiwa')), tr('Imefungwa')],
            selected: _status,
            fontSize: 13,
            onChanged: (v) {
              tick();
              setState(() => (_status = v, _tickets = null));
              _load();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: AnimatedSwitcher(
              duration: Motion.of(context, Motion.base),
              child: list == null
                  ? ListView(key: const ValueKey('wait'), children: [
                      Padding(padding: const EdgeInsets.only(top: 60), child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))),
                    ])
                  : list.isEmpty
                      ? ListView(key: ValueKey('empty$_status'), children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(32, 60, 32, 0),
                            child: Column(children: [
                              const Icon(Icons.mark_chat_read_outlined, size: 40, color: Color(0xFFB8C4C0)),
                              const SizedBox(height: 10),
                              Text(_status == 'open' ? tr('Hakuna anayesubiri jibu.') : tr('Hakuna hapa.'), style: const TextStyle(color: sMuted)),
                            ]),
                          ),
                        ])
                      : ListView.separated(
                          key: ValueKey('list$_status'),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => Appear(index: i.clamp(0, 8), child: ticketRow(context, widget.session, list[i], onBack: _load)),
                        ),
            ),
          ),
        ),
      ]),
    );
  }
}
