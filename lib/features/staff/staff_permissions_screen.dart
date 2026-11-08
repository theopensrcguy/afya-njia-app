import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/pin_fields.dart';
import '../../core/session.dart';
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

  /// Name, then a PIN typed twice. They start as a helper with the defaults;
  /// on the shop's phone they can sign in at once, on their own phone it
  /// waits for approval under Simu (as for any new phone).
  Future<void> _addPerson() async {
    final name = await askText(context, title: tr('Mfanyakazi mpya'), label: tr('Jina (litaonekana kwenye skrini ya PIN)'), required: true);
    if (name == null || !mounted) return;
    final pin = await askNewPin(context,
        title: tr('PIN ya muda ya :name', {'name': name}), message: tr('Ataitumia mara moja tu kuingia, kisha atachagua PIN yake mwenyewe.'));
    if (pin == null || !mounted) return;
    // How they sign in on a new phone or a computer, where no names are shown.
    final phone = await askText(context,
        title: tr('Namba ya simu ya :name', {'name': name}),
        label: tr('Namba ya simu (si lazima sasa)'),
        hint: '0712 345 678',
        helper: tr('Ataingia nayo kwenye simu mpya au kompyuta'));
    if (!mounted) return;
    try {
      await widget.session.api.post('staff', {'name': name, 'pin': pin, if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim()});
      _toast(tr(':name ameongezwa. PIN hii ni ya muda: akiingia mara ya kwanza atachagua yake mwenyewe.', {'name': name}));
      _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? dangerRed : null));
  }

  @override
  Widget build(BuildContext context) {
    final staff = (((_data ?? const {})['staff'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final labels = _labels(_data);
    return Scaffold(
      appBar: AppBar(title: const T('Wafanyakazi na ruhusa'), backgroundColor: pageBackground),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPerson,
        backgroundColor: brandGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const T('Ongeza mfanyakazi'),
      ),
      body: _data == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const CircularProgressIndicator())
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
                      decoration: softCard(radius: 18),
                      child: ListTile(
                        leading: const Icon(Icons.verified_user_outlined, color: brandGreen),
                        title: const T('Wewe (mmiliki)', style: TextStyle(fontWeight: FontWeight.w800)),
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
                  if (staff.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 32), child: T('Hakuna wafanyakazi bado.', textAlign: TextAlign.center)),
                  for (final s in staff)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => StaffDetailScreen(session: widget.session, data: _data!, staffId: asInt(s['id'])),
                            ));
                            if (mounted) _load();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                  child: Text('${s['name']}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: s['is_active'] == false ? mutedText : inkColor,
                                      )),
                                ),
                                if (s['is_active'] == false) _grantChip(tr('Amesimamishwa'), false),
                                const Icon(Icons.chevron_right),
                              ]),
                              Text(
                                s['phone'] == null ? tr('Hana namba ya kuingia (simu mpya / kompyuta)') : tr('Namba: :a', {'a': s['phone']}),
                                style: TextStyle(fontSize: 12, color: s['phone'] == null ? warnAmber : mutedText),
                              ),
                              const SizedBox(height: 6),
                              Wrap(spacing: 6, runSpacing: 4, children: [
                                for (final g in (s['grants'] as List).cast<Map<String, dynamic>>())
                                  _grantChip(labels[g['permission']] ?? '${g['permission']}', g['expires_at'] != null),
                              ]),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

Map<String, String> _labels(Map<String, dynamic>? data) => {
      for (final c in ((data?['catalogue'] as List?) ?? const []).cast<Map<String, dynamic>>()) '${c['key']}': '${c['label']}',
    };

Widget _grantChip(String label, bool timed) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: timed ? const Color(0xFFFBEFD6) : mintSoft, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (timed) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.schedule, size: 12, color: warnAmber)),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
    );

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

  @override
  Widget build(BuildContext context) {
    final catalogue = (widget.data['catalogue'] as List).cast<Map<String, dynamic>>();
    final bundles = (widget.data['bundles'] as List).cast<Map<String, dynamic>>();
    final active = _active;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final c in catalogue) {
      groups.putIfAbsent('${c['group']}', () => []).add(c);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${_person['name']}'),
        backgroundColor: pageBackground,
        actions: [
          IconButton(tooltip: tr('Historia'), onPressed: _history, icon: const Icon(Icons.history)),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'pin' => _changePin(),
              'phone' => _phone(),
              'off' => _deactivate(),
              _ => _activate(),
            },
            itemBuilder: (_) => [
              if (_activeNow) const PopupMenuItem(value: 'pin', child: T('Weka upya PIN')),
              if (_activeNow) const PopupMenuItem(value: 'phone', child: T('Namba ya kuingia')),
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
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            if (!_activeNow)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFFDE7E4), borderRadius: BorderRadius.circular(16)),
                child: Text(
                  tr('Amesimamishwa: hawezi kuingia kwenye simu yoyote. Historia yake yote imebaki. Menyu (⋮) › Rudisha kazini kumrudisha.'),
                  style: TextStyle(color: Color(0xFF8F1D14), fontWeight: FontWeight.w700),
                ),
              ),
            StaffProfileCard(api: _api, staffId: widget.staffId, active: _activeNow),
            const T('Weka kwa haraka', style: TextStyle(color: mutedText)),
            const SizedBox(height: 8),
            Row(children: [
              for (final b in bundles)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: _activeNow ? () => _bundle(b) : null, // nothing to switch while deactivated
                      style: OutlinedButton.styleFrom(backgroundColor: cardColor, minimumSize: const Size.fromHeight(46)),
                      child: Text('${b['label']}'),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            for (final entry in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6, top: 4),
                child: Text(entry.key, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: softCard(radius: 18),
                child: Column(children: [
                  for (final c in entry.value)
                    SwitchListTile(
                      value: active.containsKey(c['key']),
                      activeThumbColor: Colors.white,
                      activeTrackColor: brandGreen,
                      title: Text('${c['label']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        active[c['key']] != null
                            ? tr(':a\nHadi :b', {'a': c['description'], 'b': _until(active[c['key']]!)})
                            : '${c['description']}',
                        style: TextStyle(fontSize: 12, color: active[c['key']] != null ? warnAmber : mutedText),
                      ),
                      onChanged: _activeNow ? (on) => _toggle('${c['key']}', '${c['label']}', on) : null,
                    ),
                ]),
              ),
            ],
            Text(
              tr('Ruhusa ya kusimamia wafanyakazi na ruhusa ni ya mmiliki peke yake; haiwezi kutolewa.'),
              style: TextStyle(color: mutedText, fontSize: 12),
            ),
          ],
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
