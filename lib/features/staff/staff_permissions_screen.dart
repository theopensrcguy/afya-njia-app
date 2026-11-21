import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

import '../../core/loader.dart';
import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/form_style.dart';
import '../../core/format.dart';
import '../../core/phone_field.dart';
import '../../core/pin_fields.dart';
import '../../core/session.dart';
import '../../core/share_export.dart';
import '../../core/smooth.dart';
import 'staff_profile.dart';
import '../../core/i18n.dart';

/// Owner only: who may do what, and until when.
///
/// "No one is bigger than the system": the owner hands over decisions when
/// busy or away (for a day, a week, or for good) and takes them back with
/// one switch. Managing permissions itself can never be handed over.
class StaffPermissionsScreen extends StatefulWidget {
  const StaffPermissionsScreen({super.key, required this.session});

  final Session session;

  @override
  State<StaffPermissionsScreen> createState() => _StaffPermissionsScreenState();
}

class _StaffPermissionsScreenState extends State<StaffPermissionsScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  // v0.48: find someone by name, phone or what they may do; working / left / for a time.
  final _q = TextEditingController();
  String _chip = 'all';

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _shown(Map<String, dynamic> s, Map<String, String> labels) {
    final grants = (s['grants'] as List).cast<Map<String, dynamic>>();
    final ok = switch (_chip) {
      'on' => s['is_active'] != false,
      'off' => s['is_active'] == false,
      'timed' => grants.any((g) => g['expires_at'] != null),
      _ => true,
    };
    if (!ok) return false;
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    return '${s['name']}'.toLowerCase().contains(q) ||
        (digits.length >= 3 && '${s['phone'] ?? ''}'.replaceAll(RegExp(r'\D'), '').contains(digits)) ||
        grants.any((g) => (labels[g['permission']] ?? '${g['permission']}').toLowerCase().contains(q));
  }

  Future<void> _print() async {
    final how = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: T('Orodha ya wafanyakazi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: T('Jina, nafasi, simu, ruhusa na tangu lini. Bila NIDA wala taarifa binafsi.', style: TextStyle(fontSize: 12.5, color: mutedText)),
          ),
          ListTile(leading: const Icon(Icons.print_outlined), title: const T('Chapisha / Hifadhi PDF'), onTap: () => Navigator.of(sheet).pop('open')),
          ListTile(leading: const Icon(Icons.chat_outlined), title: const T('Tuma kwa WhatsApp'), onTap: () => Navigator.of(sheet).pop('wa')),
          ListTile(leading: const Icon(Icons.link_rounded), title: const T('Nakili kiungo'), onTap: () => Navigator.of(sheet).pop('copy')),
        ]),
      ),
    );
    if (how != null && mounted) await shareStaffList(context, api: widget.session.api, how: how);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final d = await widget.session.api.get('staff/permissions') as Map<String, dynamic>;
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// v0.48.3: one sheet like Sajili mteja: name, number, the role as a card,
  /// and a temporary PIN (typed or made up). Msimamizi gets that bundle at once.
  Future<void> _addPerson() async {
    final bundles = (((_data ?? const {})['bundles'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF5F8F7),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (_) => _AddStaffSheet(api: widget.session.api, bundles: bundles),
    );
    if (r == null || !mounted) return;
    _toast(r['joined'] == true ? '${r['message']}' : tr(':name ameongezwa. PIN hii ni ya muda: akiingia mara ya kwanza atachagua yake mwenyewe.', {'name': r['name']}));
    _load();
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? dangerRed : null));
  }

  Future<void> _openPerson(Map<String, dynamic> s) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => StaffDetailScreen(session: widget.session, data: _data!, staffId: asInt(s['id']))));
    if (mounted) _load();
  }

  /// Who, their role, and what they may do as areas ("Mauzo 3/4") instead of a wall of chips.
  Widget _personCard(Map<String, dynamic> s) {
    final active = s['is_active'] != false;
    final grants = (s['grants'] as List).cast<Map<String, dynamic>>();
    final have = {for (final g in grants) '${g['permission']}'};
    final timed = grants.where((g) => g['expires_at'] != null).toList();
    final labels = _labels(_data);
    final groups = permissionGroups(_data).entries.where((e) => e.value.any((c) => have.contains(c['key']))).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        onTap: () => _openPerson(s),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: active ? 1 : .62,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Hero(tag: 'staff-${s['id']}', child: staffAvatar('${s['name']}', asInt(s['id']), dim: !active)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text('${s['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
                      const SizedBox(width: 6),
                      _rolePill(roleOf(s, _data)),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      s['phone'] == null ? tr('Hana namba ya kuingia') : '${s['phone']}',
                      style: TextStyle(fontSize: 12, color: s['phone'] == null ? warnAmber : mutedText),
                    ),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: mutedText),
              ]),
              if (active && groups.isNotEmpty) ...[
                const SizedBox(height: 10),
                LayoutBuilder(builder: (context, box) {
                  final w = (box.maxWidth - 6) / 2;
                  return Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final e in groups)
                      Container(
                        width: w,
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                        decoration: BoxDecoration(color: const Color(0xFFF6F9F8), borderRadius: BorderRadius.circular(11)),
                        child: Row(children: [
                          Icon(groupIcon(e.value), size: 15, color: brandGreen),
                          const SizedBox(width: 6),
                          Expanded(child: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                          Text('${e.value.where((c) => have.contains(c['key'])).length}/${e.value.length}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    for (final g in timed)
                      Container(
                        width: w,
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                        decoration: BoxDecoration(color: warnSoft, borderRadius: BorderRadius.circular(11)),
                        child: Row(children: [
                          const Icon(Icons.schedule_rounded, size: 15, color: warnAmber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('${labels[g['permission']] ?? g['permission']} · ${_shortUntil('${g['expires_at']}')}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: warnAmber, fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ),
                  ]);
                }),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final everyone = (((_data ?? const {})['staff'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final labels = _labels(_data);
    final staff = everyone.where((s) => _shown(s, labels)).toList();
    final timed = everyone.where((s) => (s['grants'] as List).cast<Map<String, dynamic>>().any((g) => g['expires_at'] != null)).length;
    final left = everyone.where((s) => s['is_active'] == false).length;
    return Scaffold(
      appBar: AppBar(
        title: const T('Wafanyakazi na ruhusa'),
        backgroundColor: pageBackground,
        actions: [IconButton(tooltip: tr('Chapisha orodha'), onPressed: _data == null ? null : _print, icon: const Icon(Icons.print_outlined))],
      ),
      backgroundColor: pageBackground,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPerson,
        backgroundColor: const Color(0xFF0E3B31),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const T('Ongeza mfanyakazi'),
      ),
      body: _data == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const AfyaLoader())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
                children: [
                  Text(
                    tr('Mmiliki ana ruhusa zote daima. Hapa unawapa wafanyakazi ruhusa, kwa muda au kudumu, na kuziondoa wakati wowote.'),
                    style: TextStyle(color: mutedText, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  // The owner's own sign-in number (new phone, computer).
                  if (_data!['owner'] is Map)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                        leading: staffAvatar('${(_data!['owner'] as Map)['name']}', 0, onDark: true, size: 40),
                        title: Text(tr(':name · Mmiliki', {'name': (_data!['owner'] as Map)['name']}), style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text((_data!['owner'] as Map)['phone'] == null
                            ? tr('Weka namba yako: utaihitaji kuingia kwenye simu mpya au kompyuta')
                            : tr('Namba ya kuingia: :a', {'a': (_data!['owner'] as Map)['phone']})),
                        trailing: TextButton(
                          onPressed: () async {
                            final o = (_data!['owner'] as Map).cast<String, dynamic>();
                            if (await editSignInPhone(context, widget.session.api, asInt(o['id']), tr('yako'), o['phone'] as String?)) _load();
                          },
                          child: const T('Badilisha'),
                        ),
                      ),
                    ),
                  if (everyone.length > 3) ...[
                    TextField(
                      controller: _q,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: tr('Tafuta jina, simu au ruhusa'),
                        isDense: true,
                        suffixIcon: _q.text.isEmpty
                            ? null
                            : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_q.clear)),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (everyone.isNotEmpty)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final (k, label, n) in [
                          ('all', tr('Wote'), everyone.length),
                          ('on', tr('Kazini'), everyone.length - left),
                          if (left > 0) ('off', tr('Wameacha'), left),
                          if (timed > 0) ('timed', tr('Ruhusa za muda'), timed),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('$label $n'),
                              selected: _chip == k,
                              showCheckmark: false,
                              onSelected: (_) {
                                tick();
                                setState(() => _chip = k);
                              },
                            ),
                          ),
                      ]),
                    ),
                  const SizedBox(height: 10),
                  if (everyone.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 32), child: T('Hakuna wafanyakazi bado.', textAlign: TextAlign.center)),
                  if (everyone.isNotEmpty && staff.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 24), child: T('Hakuna anayelingana na utafutaji huu.', textAlign: TextAlign.center, style: TextStyle(color: mutedText))),
                  for (final (i, s) in staff.indexed) Appear(index: i.clamp(0, 8), child: _personCard(s)),
                ],
              ),
            ),
    );
  }
}

/// "Msaidizi", "Msimamizi", or "Ruhusa maalum" when the switches don't match a bundle.
String roleOf(Map<String, dynamic> person, Map<String, dynamic>? data) {
  final have = {for (final g in ((person['grants'] as List?) ?? const []).cast<Map<String, dynamic>>()) '${g['permission']}'};
  if (person['is_active'] == false) return tr('Ameacha');
  if (have.isEmpty) return tr('Hana ruhusa');
  for (final b in ((data?['bundles'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
    final want = {for (final p in (b['permissions'] as List? ?? const [])) '$p'};
    if (want.length == have.length && want.containsAll(have)) return '${b['label']}';
  }
  return tr('Ruhusa maalum');
}

/// An area's icon, by the first permission in it (the group names are translated).
IconData groupIcon(List<Map<String, dynamic>> perms) => switch ('${perms.first['key']}') {
      'sell' || 'void_any_sale' || 'big_discount' || 'view_shop_sales' => Icons.point_of_sale_rounded,
      'sell_on_credit' || 'manage_credit' => Icons.receipt_long_outlined,
      'view_customers' => Icons.people_alt_outlined,
      'receive' || 'confirm_deliveries' || 'receive_unconfirmed' || 'prepare_orders' => Icons.local_shipping_outlined,
      'view_stock' || 'count_stock' || 'adjust_stock' || 'transfer_stock' => Icons.inventory_2_outlined,
      'edit_prices' || 'view_costs' || 'record_expenses' => Icons.payments_outlined,
      _ => Icons.phonelink_lock_outlined,
    };

/// Catalogue grouped by area, in the server's order.
Map<String, List<Map<String, dynamic>>> permissionGroups(Map<String, dynamic>? data) {
  final out = <String, List<Map<String, dynamic>>>{};
  for (final c in ((data?['catalogue'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
    out.putIfAbsent('${c['group']}', () => []).add(c);
  }
  return out;
}

const _avatarTones = [(Color(0xFFDDF3EA), Color(0xFF156B55)), (Color(0xFFE6F1FB), Color(0xFF185FA5)), (Color(0xFFFDF1DC), Color(0xFF8A5300)), (Color(0xFFEEEDFE), Color(0xFF3C3489))];

Widget staffAvatar(String name, int id, {double size = 42, bool dim = false, bool onDark = false}) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  final initials = parts.isEmpty ? '?' : (parts.length == 1 ? parts.first.substring(0, parts.first.length.clamp(0, 2)) : '${parts.first[0]}${parts.last[0]}');
  final (bg, fg) = dim ? (const Color(0xFFEFF3F1), mutedText) : (onDark ? (const Color(0xFF3DDC97), const Color(0xFF0E3B31)) : _avatarTones[id % _avatarTones.length]);
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * .32)),
    child: Text(initials.toUpperCase(), style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: size * .34)),
  );
}

Widget _rolePill(String role) {
  final (bg, fg) = switch (role) {
    'Msimamizi' || 'Supervisor' => (infoSoft, infoBlue),
    'Msaidizi' || 'Helper' => (primarySoft, brandGreen),
    _ when role == tr('Ameacha') || role == tr('Hana ruhusa') => (const Color(0xFFEFF3F1), mutedText),
    _ => (warnSoft, warnAmber),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
    child: Text(role, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
  );
}

Map<String, String> _labels(Map<String, dynamic>? data) => {
      for (final c in ((data?['catalogue'] as List?) ?? const []).cast<Map<String, dynamic>>()) '${c['key']}': '${c['label']}',
    };

/// "hadi 8 Nov": short, for a tile.
String _shortUntil(String iso) => tr('hadi :d', {'d': swahiliDate(DateTime.parse(iso).toLocal())});

/// "18:00 Jumamosi, 8 Nov": when a time-limited grant ends.
String _until(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${formatTime(d)} ${swahiliDate(d)}';
}

/// One person's permissions: a switch each, grouped; bundles; history.
class StaffDetailScreen extends StatefulWidget {
  const StaffDetailScreen({super.key, required this.session, required this.data, required this.staffId});

  final Session session;
  final Map<String, dynamic> data; // catalogue + bundles (+ a first copy of the staff list)
  final int staffId;

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  late Map<String, dynamic> _person = _find(widget.data);
  bool _busy = false;

  ApiClient get _api => widget.session.api;

  Map<String, dynamic> _find(Map<String, dynamic> data) =>
      ((data['staff'] as List).cast<Map<String, dynamic>>()).firstWhere((s) => asInt(s['id']) == widget.staffId);

  /// Active grants: permission -> expires_at (null = until changed).
  Map<String, String?> get _active => {
        for (final g in (_person['grants'] as List).cast<Map<String, dynamic>>()) '${g['permission']}': g['expires_at'] as String?,
      };

  Future<void> _reload() async {
    final d = await _api.get('staff/permissions') as Map<String, dynamic>;
    if (mounted) setState(() => _person = _find(d));
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: dangerRed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Mpaka lini?" Until when? Null = until the owner changes it.
  /// Returns false if cancelled.
  Future<(bool, DateTime?)> _askUntil(String what) async {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59);
    final options = <(String, DateTime?)>[
      (tr('Leo tu (hadi saa 5:59 usiku)'), endOfToday),
      (tr('Siku 3'), endOfToday.add(const Duration(days: 3))),
      (tr('Wiki 1'), endOfToday.add(const Duration(days: 7))),
      (tr('Mwezi 1'), endOfToday.add(const Duration(days: 30))),
      (tr('Kudumu (hadi niiondoe)'), null),
    ];
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: cardColor,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tr(':what: mpaka lini?', {'what': what}), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          for (var i = 0; i < options.length; i++)
            ListTile(
              leading: Icon(options[i].$2 == null ? Icons.all_inclusive : Icons.schedule),
              title: Text(options[i].$1),
              subtitle: options[i].$2 == null ? null : Text(tr('Inaisha :a', {'a': _until(options[i].$2!.toIso8601String())})),
              onTap: () => Navigator.of(sheet).pop(i),
            ),
        ]),
      ),
    );
    if (picked == null) return (false, null);
    return (true, options[picked].$2);
  }

  Future<void> _toggle(String key, String label, bool on) async {
    if (on) {
      final (ok, until) = await _askUntil(label);
      if (!ok) return;
      await _run(
        // UTC on the wire, so the server's timezone can't shift the end time.
        () => _api.post('staff/${widget.staffId}/grants', {'permission': key, 'expires_at': until?.toUtc().toIso8601String()}),
        until == null ? tr(':label: imetolewa.', {'label': label}) : tr(':label: imetolewa hadi :a.', {'label': label, 'a': _until(until.toIso8601String())}),
      );
    } else {
      await _run(() => _api.delete('staff/${widget.staffId}/grants/$key'), tr(':label: imeondolewa.', {'label': label}));
    }
  }

  Future<void> _bundle(Map<String, dynamic> b) async {
    final (ok, until) = await _askUntil('${b['label']}');
    if (!ok) return;
    await _run(
      () => _api.post('staff/${widget.staffId}/bundle', {'bundle': b['key'], 'expires_at': until?.toUtc().toIso8601String()}),
      tr('Sasa ni :a.', {'a': b['label']}),
    );
  }

  bool get _activeNow => _person['is_active'] != false;

  Future<void> _phone() async {
    if (await editSignInPhone(context, _api, widget.staffId, tr('ya :a', {'a': _person['name']}), _person['phone'] as String?)) {
      _reload();
    }
  }

  Future<void> _changePin() async {
    final pin = await askNewPin(context,
        title: tr('Weka upya PIN ya :a', {'a': _person['name']}),
        message: tr('Kwa PIN iliyosahauliwa au iliyoonekana. Atatolewa kwenye simu zote sasa hivi, na akiingia kwa PIN hii ya muda atachagua yake mwenyewe.'));
    if (pin == null || !mounted) return;
    await _run(() => _api.patch('staff/${widget.staffId}/pin', {'pin': pin}),
        tr('PIN imewekwa upya. :a ametolewa kwenye simu zote.', {'a': _person['name']}));
  }

  /// Someone leaves: no sign-in anywhere, signed out on every phone now,
  /// permissions ended, and the phones the owner ticks removed. Their own
  /// phones are ticked; a phone others also use (the counter phone) is not.
  Future<void> _deactivate() async {
    final phones = (await _api.get('staff/${widget.staffId}/devices') as List)
        .cast<Map<String, dynamic>>()
        .where((d) => d['status'] != 'revoked')
        .toList();
    if (!mounted) return;
    final remove = {for (final d in phones) if (d['shared'] != true) asInt(d['id'])};

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setLocal) => AlertDialog(
          title: Text(tr('Simamisha :a?', {'a': _person['name']})),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const T('Hataweza kuingia, na atatolewa kwenye simu zote sasa hivi. Ruhusa zake zinaisha. Mauzo na historia yake vinabaki.'),
              if (phones.isNotEmpty) ...[
                const SizedBox(height: 12),
                const T('Ondoa pia simu hizi kwenye simu zinazoruhusiwa:', style: TextStyle(fontWeight: FontWeight.w700)),
                for (final p in phones)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: remove.contains(asInt(p['id'])),
                    onChanged: (v) => setLocal(() => v == true ? remove.add(asInt(p['id'])) : remove.remove(asInt(p['id']))),
                    title: Text('${p['name']}'),
                    subtitle: p['shared'] == true ? const T('Inatumiwa na wengine pia (mf. simu ya duka)') : null,
                  ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(d).pop(false), child: const T('Ghairi')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: dangerRed),
              onPressed: () => Navigator.of(d).pop(true),
              child: const T('Simamisha'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => _api.post('staff/${widget.staffId}/deactivate', {'revoke_device_ids': remove.toList()}),
      tr(':a amesimamishwa.', {'a': _person['name']}),
    );
  }

  Future<void> _activate() =>
      _run(() => _api.post('staff/${widget.staffId}/activate'), tr(':a amerudi kazini (ruhusa za msaidizi).', {'a': _person['name']}));

  Future<void> _history() async {
    final rows = (await _api.get('staff/${widget.staffId}/permission-history') as List).cast<Map<String, dynamic>>();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: cardColor,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            const T('Historia ya ruhusa', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final r in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(r['active'] == true ? Icons.check_circle : Icons.remove_circle_outline,
                    color: r['active'] == true ? brandGreen : mutedText),
                title: Text('${r['label']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  tr('Imetolewa :a:b', {'a': _until('${r['granted_at']}'), 'b': r['granted_by'] == null ? tr(' (mwanzo)') : tr(' na :a', {'a': r['granted_by']})}),
                  if (r['expires_at'] != null) tr('Hadi :a', {'a': _until('${r['expires_at']}')}),
                  if (r['revoked_at'] != null) tr('Imeondolewa :a na :b', {'a': _until('${r['revoked_at']}'), 'b': r['revoked_by']}),
                ].join('\n')),
              ),
          ],
        ),
      ),
    );
  }

  final Set<String> _openGroups = {};

  /// Big quick actions under the header: what an owner does most with a person.
  Widget _quick(IconData icon, String label, VoidCallback? onTap) => Expanded(
        child: Pressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Icon(icon, size: 20, color: onTap == null ? const Color(0xFFB7C6C0) : brandGreen),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: onTap == null ? mutedText : inkColor)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bundles = (widget.data['bundles'] as List).cast<Map<String, dynamic>>();
    final active = _active;
    final groups = permissionGroups(widget.data);
    final role = roleOf(_person, widget.data);
    final phone = _person['phone'] as String?;

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        backgroundColor: pageBackground,
        actions: [
          IconButton(tooltip: tr('Historia'), onPressed: _history, icon: const Icon(Icons.history_rounded)),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'off' => _deactivate(),
              _ => _activate(),
            },
            itemBuilder: (_) => [
              if (_activeNow)
                const PopupMenuItem(value: 'off', child: T('Simamisha (ameondoka)', style: TextStyle(color: dangerRed)))
              else
                const PopupMenuItem(value: 'on', child: T('Rudisha kazini')),
            ],
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy, // one change at a time
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: _busy ? .7 : 1,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: staggered([
              // Who: dark header with the role.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF0E3B31), borderRadius: BorderRadius.circular(24)),
                child: Row(children: [
                  Hero(tag: 'staff-${widget.staffId}', child: staffAvatar('${_person['name']}', widget.staffId, size: 52, onDark: true, dim: !_activeNow)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_person['name']}', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text([role, phone ?? tr('hana namba ya kuingia')].join(' · '), style: const TextStyle(color: Color(0xFFB7D3C9), fontSize: 12.5)),
                    ]),
                  ),
                ]),
              ),
              if (!_activeNow)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: dangerSoft, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Expanded(
                      child: T('Amesimamishwa: hawezi kuingia. Historia yake imebaki.', style: TextStyle(color: Color(0xFF8F1D14), fontWeight: FontWeight.w700)),
                    ),
                    TextButton(onPressed: _activate, child: const T('Rudisha')),
                  ]),
                ),
              const SizedBox(height: 10),
              Row(children: [
                _quick(Icons.call_outlined, tr('Piga'), phone == null ? null : () => launchUrl(Uri.parse('tel:${phone.replaceAll(' ', '')}'))),
                const SizedBox(width: 8),
                _quick(Icons.key_outlined, tr('PIN mpya'), _activeNow ? _changePin : null),
                const SizedBox(width: 8),
                _quick(Icons.smartphone_rounded, tr('Namba'), _activeNow ? _phone : null),
              ]),
              // Role: the two ready-made sets as cards.
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: const T('Kazi yake', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mutedText)),
              ),
              Row(children: [
                for (final (i, b) in bundles.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Pressable(
                      onTap: _activeNow && role != '${b['label']}' ? () => _bundle(b) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: role == '${b['label']}' ? brandGreen : Colors.transparent, width: 1.6),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text('${b['label']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                            if (role == '${b['label']}') const Icon(Icons.check_circle_rounded, color: brandGreen, size: 18),
                          ]),
                          Text(tr('ruhusa :n', {'n': (b['permissions'] as List).length}), style: const TextStyle(fontSize: 12, color: mutedText)),
                        ]),
                      ),
                    ),
                  ),
                ],
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: const T('Anachoruhusiwa, kwa eneo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: mutedText)),
              ),
              for (final entry in groups.entries) _groupCard(entry.key, entry.value, active),
              const SizedBox(height: 6),
              // Private details: folded, they're rarely needed.
              Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                clipBehavior: Clip.antiAlias,
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: const Icon(Icons.lock_outline_rounded, color: brandGreen),
                    title: const T('Taarifa binafsi', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: const T('NIDA, mtu wa dharura, makazi', style: TextStyle(fontSize: 12, color: mutedText)),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [StaffProfileCard(api: _api, staffId: widget.staffId, active: _activeNow)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
                child: Text(tr('Ruhusa ya kusimamia wafanyakazi na ruhusa ni ya mmiliki peke yake; haiwezi kutolewa.'),
                    style: const TextStyle(color: mutedText, fontSize: 12)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// One area: icon, "3 kati ya 4", folds open to its switches.
  Widget _groupCard(String name, List<Map<String, dynamic>> perms, Map<String, String?> active) {
    final on = perms.where((c) => active.containsKey(c['key'])).length;
    final open = _openGroups.contains(name);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => open ? _openGroups.remove(name) : _openGroups.add(name)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: on > 0 ? primarySoft : const Color(0xFFF2F6F4), borderRadius: BorderRadius.circular(11)),
                child: Icon(groupIcon(perms), size: 18, color: on > 0 ? brandGreen : mutedText),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              Text(tr(':a kati ya :b', {'a': on, 'b': perms.length}), style: TextStyle(fontSize: 12, color: on > 0 ? brandGreen : mutedText, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              AnimatedRotation(turns: open ? .5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.expand_more_rounded, color: mutedText)),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !open
              ? const SizedBox(width: double.infinity)
              : Column(children: [
                  for (final c in perms)
                    SwitchListTile(
                      value: active.containsKey(c['key']),
                      activeThumbColor: Colors.white,
                      activeTrackColor: brandGreen,
                      title: Text('${c['label']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      subtitle: Text(
                        active[c['key']] != null ? tr(':a\nHadi :b', {'a': c['description'], 'b': _until(active[c['key']]!)}) : '${c['description']}',
                        style: TextStyle(fontSize: 12, color: active[c['key']] != null ? warnAmber : mutedText),
                      ),
                      onChanged: _activeNow ? (v) => _toggle('${c['key']}', '${c['label']}', v) : null,
                    ),
                ]),
        ),
      ]),
    );
  }
}

/// Ongeza mfanyakazi (v0.48.3): one sheet. Name, number, the role as a card,
/// a temporary PIN they replace at first sign-in. Pops the server's answer.
class _AddStaffSheet extends StatefulWidget {
  const _AddStaffSheet({required this.api, required this.bundles});

  final ApiClient api;
  final List<Map<String, dynamic>> bundles;

  @override
  State<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends State<_AddStaffSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  late String _bundle = widget.bundles.isEmpty ? '' : '${widget.bundles.first['key']}';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  /// Four digits that aren't easy (no 1111, no 1234, no 4321).
  void _makePin() {
    final r = DateTime.now().microsecondsSinceEpoch;
    var pin = '';
    for (var i = 0; pin.length < 4; i++) {
      final d = '${(r >> (i * 3)) % 10}';
      if (pin.isEmpty || (d != pin[pin.length - 1] && (int.parse(d) - int.parse(pin[pin.length - 1])).abs() != 1)) pin += d;
    }
    tick();
    setState(() => _pin.text = pin);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = tr('Andika jina lake.'));
    if (_pin.text.length != 4) return setState(() => _error = tr('PIN ya muda iwe tarakimu 4 (au gusa Tengeneza).'));
    if (_phone.text.isNotEmpty && phoneProblem(_phone.text) != null) return setState(() => _error = phoneProblem(_phone.text));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.api.post('staff', {'name': name, 'pin': _pin.text, if (_phone.text.isNotEmpty) 'phone': _phone.text}) as Map<String, dynamic>;
      // Msaidizi is what a new person gets already; anything else is one more call.
      final first = widget.bundles.isEmpty ? '' : '${widget.bundles.first['key']}';
      if (_bundle.isNotEmpty && _bundle != first) {
        await widget.api.post('staff/${r['id']}/bundle', {'bundle': _bundle, 'expires_at': null});
      }
      if (mounted) Navigator.of(context).pop(r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: const Color(0xFFE3F4EA), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF0E5A44)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    T('Mfanyakazi mpya', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    T('Ataingia kwa namba yake na PIN ya muda', style: TextStyle(fontSize: 12.5, color: mutedText)),
                  ]),
                ),
                IconButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  formLabel('${tr('Jina (linaonekana kwenye skrini ya PIN)')} *'),
                  TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: formBox(tr('mf. Kelvin Mushi'))),
                  formLabel(tr('Namba ya simu')),
                  formPhone(_phone),
                  const Padding(
                    padding: EdgeInsets.only(left: 2, top: 5),
                    child: T('Anaingia nayo kwenye simu mpya au kompyuta.', style: TextStyle(fontSize: 11.5, color: mutedText)),
                  ),
                  formLabel(tr('Kazi yake')),
                  Row(children: [
                    for (final (i, b) in widget.bundles.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Pressable(
                          onTap: () {
                            tick();
                            setState(() => _bundle = '${b['key']}');
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _bundle == '${b['key']}' ? brandGreen : const Color(0xFFDCE7E2), width: _bundle == '${b['key']}' ? 1.8 : 1),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text('${b['label']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                                AnimatedScale(
                                  scale: _bundle == '${b['key']}' ? 1 : 0,
                                  duration: const Duration(milliseconds: 180),
                                  child: const Icon(Icons.check_circle_rounded, color: brandGreen, size: 18),
                                ),
                              ]),
                              Text(i == 0 ? tr('Anauza, anapokea mzigo') : tr('Zaidi: hisa, kuagiza, madeni'),
                                  style: const TextStyle(fontSize: 11.5, color: mutedText)),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ]),
                  const Padding(
                    padding: EdgeInsets.only(left: 2, top: 5),
                    child: T('Unaweza kubadilisha ruhusa moja moja baadaye.', style: TextStyle(fontSize: 11.5, color: mutedText)),
                  ),
                  formLabel('${tr('PIN ya muda')} *'),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _pin,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 4,
                        style: const TextStyle(fontSize: 20, letterSpacing: 10, fontWeight: FontWeight.w700),
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: formBox('• • • •', counter: ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _makePin,
                      icon: const Icon(Icons.casino_outlined, size: 18),
                      label: const T('Tengeneza'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ]),
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: T('Mwambie PIN hii. Akiingia mara ya kwanza atachagua yake mwenyewe.', style: TextStyle(fontSize: 11.5, color: mutedText)),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    child: _error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w700))),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: const T('Ghairi', maxLines: 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : const T('Ongeza mfanyakazi', maxLines: 1),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The number someone signs in with on a new phone or a computer (where the
/// sign-in screen shows no names). Returns true when it changed.
Future<bool> editSignInPhone(BuildContext context, ApiClient api, int userId, String whose, String? current) async {
  final v = await askText(context,
      title: tr('Namba ya kuingia :whose', {'whose': whose}),
      label: tr('Namba ya simu'),
      hint: '0712 345 678',
      initial: current ?? '',
      helper: tr('Kwenye simu mpya au kompyuta: namba hii + PIN'));
  if (v == null || !context.mounted) return false;
  try {
    await api.patch('staff/$userId/phone', {'phone': v.trim()});
    return true;
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: dangerRed));
    }
    return false;
  }
}
