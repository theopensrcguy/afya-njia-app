import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/loader.dart';
import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../../core/smooth.dart';
import 'customer_picker.dart';

/// Madeni: who owes the shop, receiving their payments, and (for whoever may
/// approve credit) approving customers and setting their optional limit.
///
/// Same rules as the web page (App\Services\CreditService on the server):
/// what someone owes is always worked out from their credit sales and
/// payments, never typed in.
class MadeniScreen extends StatefulWidget {
  const MadeniScreen({super.key, required this.session});

  final Session session;

  @override
  State<MadeniScreen> createState() => _MadeniScreenState();
}

class _MadeniScreenState extends State<MadeniScreen> {
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _requests = [];
  Map<String, dynamic> _summary = const {};
  String _filter = 'owing'; // owing | all
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.session.api;
  bool get _canApprove => widget.session.user!.can(Perm.manageCredit);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_api.get('customers'), _api.get('credit-requests')]);
      final r = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _requests = (results[1] as List).cast<Map<String, dynamic>>();
        _customers = (r['customers'] as List).cast<Map<String, dynamic>>();
        _summary = (r['summary'] as Map).cast<String, dynamic>();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> c) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerScreen(session: widget.session, id: c['id'] as int)));
    _load();
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? dangerRed : null));
  }

  Future<void> _approve(Map<String, dynamic> r) async {
    try {
      await _api.post('credit-requests/${r['id']}/approve');
      _toast(tr('Deni limekubaliwa.'));
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
    _load();
  }

  /// Decline (approver) or withdraw (the seller who asked): the medicine goes back on the shelf.
  Future<void> _decline(Map<String, dynamic> r) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: T(_canApprove ? 'Kataa ombi hili?' : 'Ondoa ombi lako?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const T('Dawa zinarudi kwenye hisa.', style: TextStyle(color: mutedText)),
          TextField(controller: reason, decoration: InputDecoration(labelText: tr('Sababu'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const T('Ghairi')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), style: FilledButton.styleFrom(backgroundColor: dangerRed),
              child: T(_canApprove ? 'Kataa' : 'Ondoa ombi')),
        ],
      ),
    );
    if (ok != true || reason.text.trim().isEmpty) return;
    try {
      await _api.post('credit-requests/${r['id']}/decline', {'reason': reason.text.trim()});
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
    _load();
  }

  Widget _request(Map<String, dynamic> r) {
    final status = '${r['status']}';
    final (bg, label) = switch (status) {
      'awaiting_credit' => (const Color(0xFFFFF3D6), tr('Inasubiri idhini')),
      'completed' => (const Color(0xFFE3F2EA), tr('Imekubaliwa: mpe mteja dawa')),
      _ => (const Color(0xFFFBE9E5), '${tr('Imekataliwa')}${r['reason'] != null ? ': ${r['reason']}' : ''}'),
    };
    final lines = ((r['lines'] as List?) ?? const []).cast<Map<String, dynamic>>()
        .map((l) => '${l['name']} ×${l['quantity']}${l['unit'] != null ? ' ${l['unit']}' : ''}').join(', ');
    return Card(
      color: bg,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${(r['customer'] as Map?)?['name'] ?? ''} · ${tr('deni')} ${formatTsh((r['credit'] as num).toInt())}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('${r['seller'] ?? ''} · ${r['receipt_number']}', style: const TextStyle(color: mutedText, fontSize: 12)),
          Text(lines, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (status == 'awaiting_credit')
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => _decline(r), child: T(_canApprove ? 'Kataa' : 'Ondoa ombi', style: const TextStyle(color: dangerRed))),
              if (_canApprove) FilledButton(onPressed: () => _approve(r), child: const T('Kubali')),
            ]),
        ]),
      ),
    );
  }

  Future<void> _add() async {
    final c = await addCustomer(context, api: _api, canApprove: _canApprove);
    if (c != null) {
      setState(() => _filter = 'all');
      _load();
    }
  }

  // ------------------------------------------------------------ v0.46.1 look
  //
  // Canvas-free rebuild after the references Tariq sent (MyDebts, All debts):
  // a dark hero with what is owed and two coloured tiles (new credit / paid
  // back this month), a ring of how old the debts are, the biggest debtors as
  // cards to swipe, then everyone with a search and filters.

  String _query = '';

  /// Days since the debt last moved (a purchase or a payment): how "cold" it is.
  int? _age(Map<String, dynamic> c) {
    final dates = [c['last_sale_at'], c['last_paid_at']].whereType<String>().map(DateTime.tryParse).whereType<DateTime>();
    if (dates.isEmpty) return null;
    final last = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    return DateTime.now().difference(last.toLocal()).inDays;
  }

  List<Map<String, dynamic>> get _owing => _customers.where((c) => ((c['owes'] as num?)?.toInt() ?? 0) > 0).toList()
    ..sort((a, b) => ((b['owes'] as num).toInt()).compareTo((a['owes'] as num).toInt()));

  List<Map<String, dynamic>> get _list {
    final q = _query.trim().toLowerCase();
    return _customers.where((c) {
      final owes = (c['owes'] as num?)?.toInt() ?? 0;
      final ok = switch (_filter) {
        'owing' => owes > 0,
        'old' => owes > 0 && (_age(c) ?? 0) > 30,
        'pending' => c['credit_status'] == 'pending',
        _ => true,
      };
      return ok && (q.isEmpty || '${c['name']}'.toLowerCase().contains(q) || '${c['phone'] ?? ''}'.contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final pending = (_summary['pending'] as num?)?.toInt() ?? 0;
    final owing = _owing;
    final list = _list;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F4),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _deep,
        foregroundColor: Colors.white,
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const T('Mteja mpya'),
      ),
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: AfyaLoader())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 110), children: [
                  Row(children: [
                    _roundBtn(Icons.chevron_left_rounded, () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 12),
                    const Expanded(child: T('Madeni', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _ink))),
                  ]),
                  const SizedBox(height: 14),
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: const TextStyle(color: dangerRed))),
                  ...staggered([
                    _hero(),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _tile(_lilac, tr('Deni jipya mwezi huu'), _summary['given_month'], _summary['given_last_month'], plus: true)),
                      const SizedBox(width: 10),
                      Expanded(child: _tile(_lime, tr('Yaliyolipwa mwezi huu'), _summary['paid_month'], _summary['paid_last_month'])),
                    ]),
                    if (owing.isNotEmpty) ...[const SizedBox(height: 18), _ageing(owing)],
                    if (owing.length > 1) ...[const SizedBox(height: 18), _biggest(owing)],
                    if (_requests.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _section(pending > 0 && _canApprove ? '${tr('Maombi ya deni')} · $pending' : tr('Maombi ya deni')),
                      for (final r in _requests) _request(r),
                    ],
                    const SizedBox(height: 18),
                    _section(tr('Wateja')),
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        hintText: tr('Tafuta jina au simu'),
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final (k, label) in [
                          ('owing', tr('Wanaodaiwa')),
                          ('old', tr('Siku 30+')),
                          if (_customers.any((c) => c['credit_status'] == 'pending')) ('pending', tr('Wanasubiri idhini')),
                          ('all', tr('Wote')),
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
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                decoration: BoxDecoration(color: _filter == k ? _ink : Colors.white, borderRadius: BorderRadius.circular(99)),
                                child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _filter == k ? Colors.white : _ink)),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(_filter == 'owing' && _query.isEmpty ? tr('Hakuna anayedaiwa sasa.') : tr('Hakuna mteja hapa.'),
                            textAlign: TextAlign.center, style: const TextStyle(color: mutedText)),
                      ),
                    for (final c in list) _row(c),
                  ]),
                ]),
              ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: _ink),
        ),
      );

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink)),
      );

  Widget _hero() {
    final total = asInt(_summary['total']);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const T('Unadai wateja', style: TextStyle(color: mutedText, fontSize: 13)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            const Text('TSh ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: mutedText)),
            CountUp(value: total, format: groupDigits, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -1)),
          ]),
        ),
        const SizedBox(height: 4),
        Text(tr('wateja :n wanadaiwa', {'n': _summary['customers'] ?? 0}), style: const TextStyle(color: mutedText)),
      ]),
    );
  }

  Widget _tile(Color bg, String label, dynamic now, dynamic before, {bool plus = false}) {
    final n = asInt(now), b = asInt(before);
    final delta = b == 0 ? null : ((n - b) / b * 100).round();
    return Container(
      height: 118,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, maxLines: 2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _ink, height: 1.2)),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('${plus && n > 0 ? '+' : ''}${groupDigits(n)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink)),
        ),
        if (delta != null)
          Row(children: [
            Icon(delta >= 0 ? Icons.arrow_circle_up_rounded : Icons.arrow_circle_down_rounded, size: 15, color: _ink),
            const SizedBox(width: 4),
            Text(tr(':p% dhidi ya mwezi uliopita', {'p': delta.abs()}), style: const TextStyle(fontSize: 11, color: _ink)),
          ]),
      ]),
    );
  }

  /// How old the money owed is: a ring of four ages, the total in the middle.
  Widget _ageing(List<Map<String, dynamic>> owing) {
    const buckets = [(7, Color(0xFF3DDC97)), (30, Color(0xFF8FB3FF)), (60, Color(0xFFF2B36B)), (1 << 30, Color(0xFFE88A7A))];
    final labels = [tr('Wiki hii'), tr('Siku 8–30'), tr('Siku 31–60'), tr('Zaidi ya 60')];
    final sums = List<int>.filled(4, 0);
    for (final c in owing) {
      final age = _age(c) ?? 0;
      final i = buckets.indexWhere((b) => age <= b.$1);
      sums[i] += (c['owes'] as num).toInt();
    }
    final total = sums.fold<int>(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _deep, borderRadius: BorderRadius.circular(26)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const T('Umri wa madeni', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const T('Siku tangu mteja alipochukua au kulipa mara ya mwisho.', style: TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 14),
        Row(children: [
          SizedBox(
            width: 132,
            height: 132,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Motion.of(context, const Duration(milliseconds: 900)),
              curve: Curves.easeOutCubic,
              builder: (_, t, _) => CustomPaint(
                painter: _Ring([for (var i = 0; i < 4; i++) (total == 0 ? 0 : sums[i] / total, buckets[i].$2)], t),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(groupDigits(total), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                    const T('TSh', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(children: [
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: buckets[i].$2, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(labels[i], style: const TextStyle(color: Colors.white70, fontSize: 12))),
                    Text(total == 0 ? '0%' : '${(sums[i] / total * 100).round()}%',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  ]),
                ),
            ]),
          ),
        ]),
        if (sums[3] > 0) ...[
          const SizedBox(height: 10),
          Pressable(
            onTap: () => setState(() => _filter = 'old'),
            child: Text(tr('TSh :a hazijaguswa zaidi ya siku 60: wakumbushe →', {'a': groupDigits(sums[3])}),
                style: const TextStyle(color: Color(0xFFF2B36B), fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
    );
  }

  /// The five who owe most, as cards to swipe.
  Widget _biggest(List<Map<String, dynamic>> owing) {
    final top = owing.take(5).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _section(tr('Wanaodaiwa zaidi')),
      SizedBox(
        height: 158,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: top.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final c = top[i];
            final age = _age(c);
            return Pressable(
              onTap: () => _open(c),
              child: Container(
                width: 140,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _avatar(c, size: 42),
                  const SizedBox(height: 8),
                  Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
                  Text(age == null ? '' : (age == 0 ? tr('Leo') : tr('siku :n', {'n': age})),
                      style: TextStyle(fontSize: 12, color: (age ?? 0) > 30 ? dangerRed : mutedText)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: const Color(0xFFEFF4F2), borderRadius: BorderRadius.circular(10)),
                    child: Text(groupDigits((c['owes'] as num).toInt()), style: const TextStyle(fontWeight: FontWeight.w800, color: _deep)),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _row(Map<String, dynamic> c) {
    final owes = (c['owes'] as num?)?.toInt() ?? 0;
    final limit = (c['credit_limit'] as num?)?.toInt();
    final age = owes > 0 ? _age(c) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: () => _open(c),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            // Ring = how much of the limit is used.
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(alignment: Alignment.center, children: [
                if (limit != null && limit > 0)
                  CircularProgressIndicator(
                    value: (owes / limit).clamp(0, 1).toDouble(),
                    strokeWidth: 3,
                    backgroundColor: const Color(0xFFE3EAE7),
                    valueColor: AlwaysStoppedAnimation(owes >= limit ? dangerRed : _deep),
                  ),
                _avatar(c, size: 40),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                Text(
                  [
                    if (c['credit_status'] == 'blocked' || c['credit_status'] == 'pending') '${c['credit_status_label']}',
                    if (age != null) age == 0 ? tr('leo') : tr('siku :n', {'n': age}),
                    if (limit != null && limit > 0) tr('ametumia :p% ya kikomo', {'p': (owes / limit * 100).round()}),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c['credit_status'] == 'blocked' || (age ?? 0) > 30 ? dangerRed : mutedText),
                ),
              ]),
            ),
            _owes(c),
          ]),
        ),
      ),
    );
  }
}

const _ink = Color(0xFF14211D);
const _deep = Color(0xFF0E3B31);
const _lilac = Color(0xFFD9CCFF);
const _lime = Color(0xFFE4F79A);

/// Initials on a soft colour picked from the name (the same person, the same colour).
Widget _avatar(Map<String, dynamic> c, {double size = 40}) {
  const colours = [Color(0xFFCDEFE0), Color(0xFFD9CCFF), Color(0xFFFFE0B8), Color(0xFFCFE3FF), Color(0xFFFBD5CF), Color(0xFFE4F79A)];
  final name = '${c['name']}'.trim();
  final initials = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: colours[name.hashCode.abs() % colours.length], shape: BoxShape.circle),
    alignment: Alignment.center,
    child: Text(initials.isEmpty ? '·' : initials, style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * .34, color: _ink)),
  );
}

class _Ring extends CustomPainter {
  _Ring(this.parts, this.t);

  final List<(double, Color)> parts;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * .12;
    final r = rect.deflate(stroke / 2);
    final bg = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(r, 0, 6.2832, false, bg);
    var start = -1.5708;
    const gap = .06;
    for (final (share, colour) in parts) {
      if (share <= 0) continue;
      final sweep = share * 6.2832 * t;
      final p = Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(r, start + gap / 2, (sweep - gap).clamp(.001, 6.3), false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_Ring old) => old.t != t || old.parts != parts;
}

/// "TSh 4,500", or "salio 1,000" when the shop owes them (a returned sale after they paid).
Widget _owes(Map<String, dynamic> c) {
  final owes = (c['owes'] as num?)?.toInt() ?? 0;
  if (owes > 0) return Text(formatTsh(owes), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15));
  if (owes < 0) return Text(tr('Ana salio :a', {'a': formatTsh(-owes)}), style: const TextStyle(color: mutedText, fontSize: 12));
  return const Text('—', style: TextStyle(color: mutedText));
}

/// One customer: what they owe, their account, receive a payment, approve / limit.
class CustomerScreen extends StatefulWidget {
  const CustomerScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  Map<String, dynamic>? _c;
  String? _error;

  ApiClient get _api => widget.session.api;
  bool get _canApprove => widget.session.user!.can(Perm.manageCredit);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _api.get('customers/${widget.id}') as Map<String, dynamic>;
      if (mounted) setState(() => _c = c);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? dangerRed : null));
  }

  Future<void> _pay() async {
    final c = _c!;
    final owes = (c['owes'] as num).toInt();
    final amount = TextEditingController(text: '$owes');
    var method = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, set) => AlertDialog(
          title: Text(tr('Pokea malipo: :name', {'name': c['name']})),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Anadaiwa :a.', {'a': formatTsh(owes)})),
            const SizedBox(height: 8),
            TextField(controller: amount, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Kiasi (TSh)'))),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 'cash', label: T('Taslimu')), ButtonSegment(value: 'mobile', label: T('Simu'))],
              selected: {method},
              onSelectionChanged: (s) => set(() => method = s.first),
            ),
            const SizedBox(height: 8),
            const T('Taslimu inaingia kwenye droo ya zamu iliyo wazi.', style: TextStyle(color: mutedText, fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const T('Ghairi')),
            FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const T('Pokea')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await _api.post('customers/${c['id']}/payments', {
        'amount': int.tryParse(amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0,
        'method': method,
      }) as Map<String, dynamic>;
      final left = (r['owes'] as num).toInt();
      _toast(left > 0 ? tr('Malipo yamepokelewa. Bado anadaiwa :a.', {'a': formatTsh(left)}) : tr('Malipo yamepokelewa. Deni limekwisha.'));
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _approve({required String status}) async {
    final c = _c!;
    final limit = TextEditingController(text: c['credit_limit'] == null ? '' : '${c['credit_limit']}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('${c['name']}: ${tr('kikomo cha deni')}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: limit,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('Kikomo cha deni (TSh, si lazima)'), hintText: tr('hakuna kikomo')),
          ),
          const SizedBox(height: 6),
          const T('Kiasi cha juu anachoweza kudaiwa kwa wakati mmoja. Acha wazi kwa bila kikomo.', style: TextStyle(color: mutedText, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const T('Ghairi')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const T('Hifadhi')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final digits = limit.text.replaceAll(RegExp(r'\D'), '');
      await _api.patch('customers/${c['id']}', {'credit_status': status, 'credit_limit': digits.isEmpty ? null : int.parse(digits)});
      _toast(tr('Imehifadhiwa.'));
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _block() async {
    try {
      await _api.patch('customers/${_c!['id']}', {'credit_status': 'blocked'});
      _toast(tr('Imehifadhiwa.'));
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  /// A polite reminder from the shop's own phone (SMS or WhatsApp), with the amount.
  Future<void> _remind(String via) async {
    final c = _c!;
    final owes = (c['owes'] as num).toInt();
    final phone = '${c['phone'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
    final text = tr('Habari :name, ni kumbusho kutoka :shop: deni lako ni :a. Asante.',
        {'name': '${c['name']}'.split(' ').first, 'shop': widget.session.user!.shopName ?? tr('dukani'), 'a': formatTsh(owes)});
    final uri = via == 'wa'
        ? Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}')
        : Uri.parse('sms:+$phone?body=${Uri.encodeComponent(text)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) _toast(tr('Haikufunguka kwenye simu hii.'), error: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF2F6F4),
        appBar: AppBar(backgroundColor: const Color(0xFFF2F6F4)),
        body: Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const AfyaLoader()),
      );
    }
    final owes = (c['owes'] as num).toInt();
    final limit = (c['credit_limit'] as num?)?.toInt();
    final statement = (c['statement'] as List).cast<Map<String, dynamic>>();
    final hasPhone = c['phone'] != null && '${c['phone']}'.length > 4;
    final phone = hasPhone ? '0${'${c['phone']}'.substring(3)}' : '';
    final paid = statement.where((s) => s['kind'] != 'sale').fold<int>(0, (a, s) => a + (s['amount'] as num).toInt());
    final taken = statement.where((s) => s['kind'] == 'sale').fold<int>(0, (a, s) => a + (s['amount'] as num).toInt());
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F4),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: staggered([
            // The dark hero: who, how much, and the two things to do.
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(28)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: Colors.white10),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                  if (_canApprove)
                    PopupMenuButton<String>(
                      iconColor: Colors.white,
                      onSelected: (v) => v == 'block' ? _block() : _approve(status: 'approved'),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'limit', child: T('Badilisha kikomo')),
                        c['credit_status'] == 'blocked'
                            ? const PopupMenuItem(value: 'unblock', child: T('Ruhusu kukopa tena'))
                            : const PopupMenuItem(value: 'block', child: T('Zuia kukopa')),
                      ],
                    ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  _avatar(c, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${c['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                      Text([if (phone.isNotEmpty) phone, '${c['credit_status_label']}'].join(' · '), style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 18),
                Text(owes >= 0 ? tr('Anadaiwa') : tr('Ana salio'), style: const TextStyle(color: Colors.white60, fontSize: 13)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    const Text('TSh ', style: TextStyle(color: Colors.white54, fontSize: 20, fontWeight: FontWeight.w700)),
                    CountUp(value: owes.abs(), format: groupDigits, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1)),
                  ]),
                ),
                if (limit != null && limit > 0) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (owes / limit).clamp(0, 1).toDouble(),
                      minHeight: 7,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(owes >= limit ? const Color(0xFFE88A7A) : _lime),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(tr('Kikomo :a · anaweza :b zaidi', {'a': formatTsh(limit), 'b': formatTsh((limit - owes).clamp(0, limit))}),
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  if (owes > 0)
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _lime, foregroundColor: _ink, minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        onPressed: _pay,
                        icon: const Icon(Icons.add_rounded),
                        label: const T('Pokea malipo', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  if (owes > 0 && hasPhone) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _ink, minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          showDragHandle: true,
                          backgroundColor: Colors.white,
                          builder: (sheet) => SafeArea(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              ListTile(leading: const Icon(Icons.sms_outlined), title: const T('Kwa SMS'), onTap: () {
                                Navigator.of(sheet).pop();
                                _remind('sms');
                              }),
                              ListTile(leading: const Icon(Icons.chat_outlined), title: const T('Kwa WhatsApp'), onTap: () {
                                Navigator.of(sheet).pop();
                                _remind('wa');
                              }),
                              ListTile(leading: const Icon(Icons.call_outlined), title: Text(tr('Piga :p', {'p': phone})), onTap: () {
                                Navigator.of(sheet).pop();
                                launchUrl(Uri.parse('tel:$phone'));
                              }),
                            ]),
                          ),
                        ),
                        icon: const Icon(Icons.notifications_active_outlined),
                        label: const T('Kumbusha', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _mini(_lilac, tr('Amechukua'), taken)),
              const SizedBox(width: 10),
              Expanded(child: _mini(_lime, tr('Amelipa'), paid)),
            ]),
            const SizedBox(height: 18),
            const T('Historia', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _ink)),
            const SizedBox(height: 10),
            if (statement.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: T('Bado hakuna deni wala malipo.', style: TextStyle(color: mutedText))),
            for (final x in statement) _line(x),
          ])),
        ),
      ),
    );
  }

  Widget _mini(Color bg, String label, int amount) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _ink)),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(formatTsh(amount), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink))),
        ]),
      );

  Widget _line(Map<String, dynamic> x) {
    final sale = x['kind'] == 'sale';
    final at = DateTime.tryParse('${x['at']}')?.toLocal();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: sale ? _lilac : _lime, borderRadius: BorderRadius.circular(14)),
          child: Icon(sale ? Icons.shopping_bag_outlined : Icons.payments_outlined, size: 20, color: _ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sale ? '${tr('Deni')} · ${x['receipt_number']}' : '${tr('Malipo')} · ${paymentLabels[x['method']] ?? x['method']}',
                style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
            Text([if (at != null) '${swahiliDate(at)} · ${formatTime(at)}', '${x['by'] ?? ''}'].where((e) => e.isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 12, color: mutedText)),
          ]),
        ),
        Text('${sale ? '+' : '−'}${groupDigits((x['amount'] as num).toInt())}',
            style: TextStyle(fontWeight: FontWeight.w800, color: sale ? _ink : const Color(0xFF1F8A66))),
      ]),
    );
  }
}

