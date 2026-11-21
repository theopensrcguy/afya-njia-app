import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/loader.dart';
import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import 'help_content.dart';

/// Msaada: ask Saola for help, and read the answers.
///
/// The owner sees every request of the shop; staff see their own. Saola's
/// replies come here, and by SMS. Same rules as the web (App\Services\Saola\SupportDesk).
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.session, this.initialTab = 0});

  final Session session;

  /// 0 Maswali · 1 Mwongozo (how to use the app) · 2 Wasiliana · 3 Maombi.
  final int initialTab;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

/// Colour and text for a request's status: whose turn it is.
(Color, Color) _statusColors(String s) => switch (s) {
      'open' => (infoSoft, infoBlue),
      'answered' => (primarySoft, primaryStrong),
      _ => (cardColor, mutedText),
    };

Widget _statusPill(Map<String, dynamic> t) {
  final (bg, fg) = _statusColors('${t['status']}');
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Text('${t['status_label']}', style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
  );
}

class _SupportScreenState extends State<SupportScreen> {
  List<Map<String, dynamic>> _tickets = [];
  Map<String, dynamic> _contact = const {};
  bool _loading = true;
  String? _error;

  // v0.48.2: answers first (Maswali), the how-to (Mwongozo), every way to reach
  // Saola (Wasiliana), then the shop's own requests (Maombi).
  late int _tab = widget.initialTab;
  String _topic = helpTopics.first;
  final _q = TextEditingController();
  int? _openQ;

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
    try {
      final d = await _api.get('support') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _tickets = (d['tickets'] as List).cast<Map<String, dynamic>>();
          _contact = ((d['contact'] as Map?) ?? const {}).cast<String, dynamic>();
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SupportTicketScreen(session: widget.session, id: id)));
    _load();
  }

  Future<void> _new() async {
    final id = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => NewSupportScreen(api: _api)));
    if (id != null) _open(id);
  }

  int get _waiting => _tickets.where((t) => t['status'] == 'answered').length;

  @override
  Widget build(BuildContext context) {
    final search = _q.text.trim().toLowerCase();
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Msaada', style: TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: _tab == 3
          ? FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add_comment_outlined), label: const T('Omba msaada'))
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
          _hero(),
          const SizedBox(height: 12),
          _tabs(),
          const SizedBox(height: 8),
          // v0.48.3: each tab slides and fades in; content rises in one item after another.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(a), child: child),
            ),
            layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
            child: Column(
              key: ValueKey('$_tab|${search.isEmpty}|$_topic'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: search.isNotEmpty
                  ? _results(search)
                  : staggered(switch (_tab) {
                      0 => _questions(),
                      1 => _guides(),
                      2 => _contacts(),
                      _ => _requests(),
                    }),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(color: const Color(0xFF0E3B31), borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const T('Tukusaidie nini leo?', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            _contact['hours'] != null ? tr('Saola wanajibu: :h', {'h': _contact['hours']}) : tr('Tafuta jibu, fuata mwongozo, au waandikie Saola.'),
            style: const TextStyle(color: Color(0xFFB7D3C9), fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white),
            cursorColor: const Color(0xFF3DDC97),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white12,
              prefixIcon: const Icon(Icons.search, color: Color(0xFFB7D3C9)),
              suffixIcon: _q.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close, color: Color(0xFFB7D3C9)), onPressed: () => setState(_q.clear)),
              hintText: tr('Tafuta swali au mwongozo…'),
              hintStyle: const TextStyle(color: Color(0xFF9FC2B6)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF3DDC97))),
            ),
          ),
        ]),
      );

  Widget _tabs() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          for (final (i, label) in [(0, tr('Maswali')), (1, tr('Mwongozo')), (2, tr('Wasiliana')), (3, tr('Maombi'))])
            Expanded(
              child: Pressable(
                onTap: () => setState(() {
                  _tab = i;
                  _q.clear();
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                  decoration: BoxDecoration(color: _tab == i ? inkColor : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label, maxLines: 1, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _tab == i ? Colors.white : inkColor)),
                      ),
                    ),
                    if (i == 3 && _waiting > 0) ...[
                      const SizedBox(width: 4),
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF3DDC97), shape: BoxShape.circle)),
                    ],
                  ]),
                ),
              ),
            ),
        ]),
      );

  Widget _qa(HelpQuestion h, int index) {
    final open = _openQ == index;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _openQ = open ? null : index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(tr(h.q), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
              AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 180), child: const Icon(Icons.expand_more_rounded, color: mutedText)),
            ]),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: open
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Text(tr(h.a), style: const TextStyle(fontSize: 13, height: 1.45, color: mutedText)),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _questions() => [
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final t in helpTopics)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(tr(t)),
                  selected: _topic == t,
                  showCheckmark: false,
                  onSelected: (_) {
                    tick();
                    setState(() {
                      _topic = t;
                      _openQ = null;
                    });
                  },
                ),
              ),
          ]),
        ),
        for (final (i, h) in helpQuestions.indexed)
          if (h.topic == _topic) _qa(h, i),
        _askSaola(),
      ];

  Widget _askSaola() => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _tab = 2),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const T('Hujapata jibu? Ongea na Saola'),
          ),
        ),
      );

  List<Widget> _guides() => [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 2),
          child: T('Jinsi ya kutumia Afya Njia, hatua kwa hatua.', style: TextStyle(fontSize: 13, color: mutedText)),
        ),
        LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - 10) / 2;
          // One height for every tile (scaled with text size), so the grid reads as a grid.
          final h = MediaQuery.textScalerOf(context).scale(122);
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (i, g) in helpGuides.indexed)
              Appear(
                index: i,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Pressable(
                    onTap: () => Navigator.of(context).push(_rise(HelpGuideScreen(guide: g))),
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: primarySoft, borderRadius: BorderRadius.circular(11)),
                            child: Icon(g.icon, color: brandGreen, size: 19),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFEEF6F2), borderRadius: BorderRadius.circular(99)),
                            child: Text(tr('hatua :n', {'n': g.steps.length}), style: const TextStyle(fontSize: 11, color: brandGreen, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                        const Spacer(),
                        Text(tr(g.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        const SizedBox(height: 1),
                        Text(tr(g.why), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: mutedText)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]);
        }),
      ];

  Widget _contactTile(IconData icon, Color bg, Color fg, String title, String? sub, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: fg, size: 21)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: mutedText)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: mutedText),
            ]),
          ),
        ),
      );

  List<Widget> _contacts() {
    final wa = '${_contact['whatsapp'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
    final phone = '${_contact['phone'] ?? ''}'.replaceAll(RegExp(r'[^\d+]'), '');
    final email = '${_contact['email'] ?? ''}';
    final shop = widget.session.user?.shopName ?? '';
    return [
      _contactTile(Icons.forum_outlined, primarySoft, brandGreen, tr('Andika ndani ya app'), tr('Picha za skrini, na historia yote'), _new),
      if (wa.isNotEmpty)
        _contactTile(Icons.chat_outlined, const Color(0xFFE3F7EA), const Color(0xFF1A7F3C), 'WhatsApp', '+$wa', () {
          final text = tr('Habari Saola, naomba msaada (:shop).', {'shop': shop});
          launchUrl(Uri.parse('https://wa.me/$wa?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
        }),
      if (phone.isNotEmpty)
        _contactTile(Icons.call_outlined, infoSoft, infoBlue, tr('Piga simu'), _contact['hours'] as String? ?? phone, () => launchUrl(Uri.parse('tel:+${phone.replaceAll('+', '')}'))),
      if (email.isNotEmpty)
        _contactTile(Icons.mail_outline_rounded, warnSoft, warnAmber, tr('Barua pepe'), email, () => launchUrl(Uri.parse('mailto:$email?subject=${Uri.encodeComponent('Afya Njia · $shop')}'))),
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 16, 4, 0),
        child: T('Saola hawatakuuliza PIN yako kamwe. Usiitume kwa mtu yeyote.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: mutedText)),
      ),
    ];
  }

  List<Widget> _requests() => [
        if (_loading) const Padding(padding: EdgeInsets.all(32), child: Center(child: AfyaLoader())),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: dangerRed))),
        if (!_loading && _tickets.isEmpty && _error == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: T('Hujaomba msaada bado. Gusa "Omba msaada" kuandika kwa Saola.', textAlign: TextAlign.center, style: TextStyle(color: mutedText)),
          ),
        for (final t in _tickets)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Pressable(
              onTap: () => _open(t['id'] as int),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${t['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Row(children: [
                        _statusPill(t),
                        if (priorityPill(t) case final p?) ...[const SizedBox(width: 6), p],
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ['#${t['id']}', t['opened_by'], if (t['last_message_at'] != null) timeAgo(DateTime.parse('${t['last_message_at']}').toLocal())].whereType<String>().join(' · '),
                            style: const TextStyle(color: mutedText, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: mutedText),
                ]),
              ),
            ),
          ),
      ];

  /// Searching looks in every question and guide at once.
  List<Widget> _results(String q) {
    final qs = [for (final (i, h) in helpQuestions.indexed) if ('${tr(h.q)} ${tr(h.a)}'.toLowerCase().contains(q)) (i, h)];
    final gs = [for (final g in helpGuides) if ('${tr(g.title)} ${tr(g.why)} ${g.steps.map(tr).join(' ')}'.toLowerCase().contains(q)) g];
    return [
      if (qs.isEmpty && gs.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: T('Hakuna jibu linalolingana.', textAlign: TextAlign.center, style: TextStyle(color: mutedText))),
      for (final g in gs)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ListTile(
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: Icon(g.icon, color: brandGreen),
            title: Text(tr(g.title), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(tr('Mwongozo · hatua :n', {'n': g.steps.length})),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(_rise(HelpGuideScreen(guide: g))),
          ),
        ),
      for (final (i, h) in qs) _qa(h, i),
      _askSaola(),
    ];
  }
}

/// One guide: why, then numbered steps on a line, like a path.
class HelpGuideScreen extends StatelessWidget {
  const HelpGuideScreen({super.key, required this.guide});

  final HelpGuide guide;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(backgroundColor: pageBackground, title: Text(tr(guide.title), style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFF0E3B31), borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(14)),
              child: Icon(guide.icon, color: const Color(0xFF3DDC97)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(tr(guide.why), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
          ]),
        ),
        const SizedBox(height: 14),
        for (final (i, step) in guide.steps.indexed)
          Appear(index: i + 1, child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 34,
                child: Column(children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: brandGreen, shape: BoxShape.circle),
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                  if (i < guide.steps.length - 1) Expanded(child: Container(width: 2, color: const Color(0xFFCFE3DA))),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Text(tr(step), style: const TextStyle(fontSize: 14, height: 1.45)),
                ),
              ),
            ]),
          )),
      ]),
    );
  }
}

/// Write to Saola (v0.48.3): pick what it's about and how much it hurts, so
/// Saola answers "I can't sell" before "how do I print", then say what happened.
/// The choices live here (not from the server) so the form opens at once.
const supportCategories = <(String, IconData, String, String)>[
  ('login', Icons.lock_outline_rounded, 'Kuingia na PIN', 'mfano Simu mpya haiingii'),
  ('sales', Icons.point_of_sale_rounded, 'Mauzo', 'mfano Siwezi kukamilisha mauzo'),
  ('stock', Icons.inventory_2_outlined, 'Hisa na mizigo', 'mfano Siwezi kuingiza mzigo'),
  ('device', Icons.smartphone_rounded, 'Simu au kifaa', 'mfano Printa haichapishi'),
  ('billing', Icons.payments_outlined, 'Malipo ya Afya Njia', 'mfano Nimelipa, bado imefungwa'),
  ('reports', Icons.insights_rounded, 'Ripoti na namba', 'mfano Namba za ripoti hazilingani'),
  ('idea', Icons.lightbulb_outline_rounded, 'Wazo jipya', 'mfano Ningependa app ifanye…'),
  ('other', Icons.more_horiz_rounded, 'Mengineyo', 'mfano Swali kuhusu…'),
];

const supportPriorities = <(String, Color, Color, String, String)>[
  ('urgent', Color(0xFFC2412D), Color(0xFFFBE9E5), 'Dharura', 'Duka haliwezi kufanya kazi: hatuwezi kuingia au kuuza.'),
  ('high', Color(0xFF8A5300), Color(0xFFFFF4DC), 'Muhimu', 'Kuna tatizo, lakini kazi inaendelea.'),
  ('normal', Color(0xFF1F8A66), Color(0xFFE7F6EF), 'Kawaida', 'Swali, ushauri au wazo.'),
];

/// The small coloured label of a ticket's priority (nothing for "Kawaida").
Widget? priorityPill(Map<String, dynamic> t) {
  final p = '${t['priority'] ?? 'normal'}';
  if (p == 'normal') return null;
  final look = supportPriorities.firstWhere((x) => x.$1 == p, orElse: () => supportPriorities.last);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: look.$3, borderRadius: BorderRadius.circular(99)),
    child: Text(tr(look.$4), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: look.$2)),
  );
}

class NewSupportScreen extends StatefulWidget {
  const NewSupportScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<NewSupportScreen> createState() => _NewSupportScreenState();
}

class _NewSupportScreenState extends State<NewSupportScreen> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String? _category;
  String _priority = 'normal';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_category == null) {
      setState(() => _error = tr('Chagua tatizo linahusu nini.'));
      return;
    }
    if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = tr('Jaza kuhusu nini, na eleza tatizo.'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final t = await widget.api.post('support', {
        'subject': _subject.text.trim(),
        'body': _body.text.trim(),
        'category': _category,
        'priority': _priority,
      }) as Map<String, dynamic>;
      if (mounted) Navigator.of(context).pop(t['id'] as int);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = supportCategories.where((c) => c.$1 == _category).firstOrNull;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F6),
      appBar: AppBar(backgroundColor: const Color(0xFFF4F8F6), title: const T('Omba msaada')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedSize(
              duration: Motion.of(context, Motion.base),
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: dangerRed, fontSize: 13))),
            ),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              style: FilledButton.styleFrom(
                backgroundColor: _priority == 'urgent' ? const Color(0xFFB4503F) : const Color(0xFF2F8A6C),
                shape: const StadiumBorder(),
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(_sending ? tr('Inatuma…') : (_priority == 'urgent' ? tr('Tuma kama dharura') : tr('Tuma kwa Saola')),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: staggered([
        _label(tr('Linahusu nini?')),
        LayoutBuilder(builder: (context, box) {
          final w = (box.maxWidth - 10) / 2;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in supportCategories)
              SizedBox(width: w, child: _categoryTile(c)),
          ]);
        }),
        const SizedBox(height: 18),
        _label(tr('Ni la haraka kiasi gani?')),
        for (final p in supportPriorities) Padding(padding: const EdgeInsets.only(bottom: 8), child: _priorityCard(p)),
        const SizedBox(height: 10),
        _label(tr('Kuhusu nini?')),
        TextField(
          controller: _subject,
          maxLength: 150,
          textCapitalization: TextCapitalization.sentences,
          decoration: _box(tr(cat?.$4 ?? 'mfano Siwezi kuingiza mzigo')),
        ),
        _label(tr('Eleza tatizo')),
        TextField(
          controller: _body,
          minLines: 5,
          maxLines: 10,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          decoration: _box(tr('Ulikuwa unafanya nini, nini kilitokea, na ujumbe gani ulionekana.')),
        ),
        const T('Usiandike PIN yako wala namba za siri. Saola hawatakuuliza PIN kamwe.', style: TextStyle(color: mutedText, fontSize: 12)),
      ])),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8, top: 4),
        child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF14211D))),
      );

  InputDecoration _box(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF8FD0B4), width: 1.4)),
      );

  Widget _categoryTile((String, IconData, String, String) c) {
    final on = _category == c.$1;
    return Pressable(
      onTap: () {
        tick();
        setState(() => (_category = c.$1, _error = null));
      },
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        curve: Motion.curve,
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFE3F4EC) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? const Color(0xFF8FD0B4) : Colors.transparent, width: 1.4),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: on ? const Color(0xFF2F8A6C) : const Color(0xFFEFF4F2), borderRadius: BorderRadius.circular(10)),
            child: Icon(c.$2, size: 17, color: on ? Colors.white : const Color(0xFF0E3B31)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr(c.$3), maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, height: 1.2, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: const Color(0xFF14211D))),
          ),
        ]),
      ),
    );
  }

  Widget _priorityCard((String, Color, Color, String, String) p) {
    final on = _priority == p.$1;
    return Pressable(
      onTap: () {
        tick();
        setState(() => _priority = p.$1);
      },
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        curve: Motion.curve,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: on ? p.$3 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? p.$2.withValues(alpha: .45) : Colors.transparent, width: 1.4),
        ),
        child: Row(children: [
          AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            width: 20,
            height: 20,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: on ? p.$2 : const Color(0xFFB8C4C0), width: on ? 6 : 2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(p.$4), style: TextStyle(fontWeight: FontWeight.w800, color: on ? p.$2 : const Color(0xFF14211D))),
              const SizedBox(height: 2),
              Text(tr(p.$5), style: const TextStyle(fontSize: 12, color: mutedText)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// One request: the conversation, a reply box, and "Funga ombi".
class SupportTicketScreen extends StatefulWidget {
  const SupportTicketScreen({super.key, required this.session, required this.id, this.saola = false});

  final Session session;
  final int id;

  /// Opened from the Saola console (v0.48.3): the shop's name on top, its initial in the circle.
  final bool saola;

  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen> {
  Map<String, dynamic>? _t;
  String? _error;
  bool _sending = false;
  final _reply = TextEditingController();

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await _api.get('support/${widget.id}') as Map<String, dynamic>;
      if (mounted) setState(() => _t = t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final t = await _api.post('support/${widget.id}/reply', {'body': text}) as Map<String, dynamic>;
      _reply.clear();
      if (mounted) setState(() => _t = t);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// A screenshot: "this is what I see" says more than a paragraph.
  Future<void> _sendPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (file == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final bytes = await file.readAsBytes();
      final text = _reply.text.trim();
      final t = await _api.upload('support/${widget.id}/reply', 'photo', bytes, file.name.contains('.') ? file.name : '${file.name}.jpg',
          fields: {if (text.isNotEmpty) 'body': text}) as Map<String, dynamic>;
      _reply.clear();
      if (mounted) setState(() => _t = t);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    try {
      final t = await _api.post('support/${widget.id}/close') as Map<String, dynamic>;
      if (mounted) setState(() => _t = t);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final messages = ((t?['messages'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final status = '${t?['status'] ?? ''}';
    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        backgroundColor: pageBackground,
        titleSpacing: 0,
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFF0E3B31), shape: BoxShape.circle),
            child: Text(widget.saola && t != null ? '${t['pharmacy'] ?? 'S'}'.characters.first.toUpperCase() : 'S',
                style: const TextStyle(color: Color(0xFF3DDC97), fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t == null ? tr('Msaada') : '${t['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              if (t != null)
                Text([if (widget.saola && t['pharmacy'] != null) '${t['pharmacy']}', '#${t['id']}', '${t['status_label']}'].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: status == 'answered' ? brandGreen : mutedText, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        actions: [
          if (t != null && status != 'closed')
            PopupMenuButton<String>(
              onSelected: (_) => _close(),
              itemBuilder: (_) => [PopupMenuItem(value: 'close', child: T('Funga ombi: tatizo limekwisha'))],
            ),
        ],
      ),
      body: t == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const AfyaLoader())
          : Column(children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(reverse: true, padding: const EdgeInsets.fromLTRB(14, 8, 14, 8), children: [
                    for (final (i, m) in messages.reversed.indexed) ...[
                      _bubble(m),
                      if (i == messages.length - 1 || _day(m) != _day(messages.reversed.elementAt(i + 1)))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: Text(_day(m), style: const TextStyle(fontSize: 11.5, color: mutedText, fontWeight: FontWeight.w600))),
                        ),
                    ],
                  ]),
                ),
              ),
              if (status == 'closed')
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: T('Ombi limefungwa. Ukiandika tena, litafunguliwa.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: mutedText)),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    IconButton(
                      tooltip: tr('Tuma picha ya skrini'),
                      onPressed: _sending ? null : _sendPhoto,
                      icon: const Icon(Icons.add_photo_alternate_outlined, color: brandGreen),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _reply,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: tr('Andika ujumbe…'),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
                      tooltip: tr('Tuma'),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }

  String _day(Map<String, dynamic> m) {
    final at = DateTime.tryParse('${m['at']}')?.toLocal();
    if (at == null) return '';
    final now = DateTime.now();
    if (at.year == now.year && at.month == now.month && at.day == now.day) return tr('Leo');
    final y = now.subtract(const Duration(days: 1));
    if (at.year == y.year && at.month == y.month && at.day == y.day) return tr('Jana');
    return swahiliDate(at);
  }

  /// The shop on the right in dark; Saola on the left in white. A screenshot inside the bubble.
  Widget _bubble(Map<String, dynamic> m) {
    final saola = m['from_saola'] == true;
    final mine = m['mine'] == true || (!saola && m['mine'] == null);
    final at = DateTime.tryParse('${m['at']}')?.toLocal();
    final time = at == null ? '' : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final body = '${m['body'] ?? ''}';
    final photo = m['photo_url'] as String?;
    final fg = mine ? Colors.white : inkColor;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        margin: const EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.fromLTRB(photo == null ? 12 : 5, photo == null ? 8 : 5, photo == null ? 12 : 5, 6),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF14211D) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (!mine)
            Padding(
              padding: EdgeInsets.only(bottom: 2, left: photo == null ? 0 : 7),
              child: Text('${m['author']}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: saola ? brandGreen : mutedText)),
            ),
          if (photo != null)
            GestureDetector(
              onTap: () => showDialog(
                context: context,
                builder: (d) => Dialog(
                  insetPadding: const EdgeInsets.all(12),
                  clipBehavior: Clip.antiAlias,
                  child: InteractiveViewer(child: Image.network(photo)),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(photo, height: 220, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(height: 60, child: Center(child: Icon(Icons.broken_image_outlined)))),
              ),
            ),
          if (body.isNotEmpty && !(photo != null && body == '📷'))
            Padding(
              padding: EdgeInsets.fromLTRB(photo == null ? 0 : 7, photo == null ? 0 : 6, photo == null ? 0 : 7, 0),
              child: Text(body, style: TextStyle(color: fg, fontSize: 14, height: 1.35)),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(top: 2, right: photo == null ? 0 : 7),
              child: Text(time, style: TextStyle(fontSize: 10.5, color: mine ? Colors.white60 : mutedText)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A page that rises and fades in (the guides): softer than the side slide.
Route<void> _rise(Widget page) => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: c, child: SlideTransition(position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(c), child: child));
      },
    );
