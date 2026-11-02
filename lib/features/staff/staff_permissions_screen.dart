import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/session.dart';

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

  @override
  Widget build(BuildContext context) {
    final staff = (((_data ?? const {})['staff'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final labels = _labels(_data);
    return Scaffold(
      appBar: AppBar(title: const Text('Wafanyakazi na ruhusa'), backgroundColor: pageBackground),
      body: _data == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  const Text(
                    'Mmiliki ana ruhusa zote daima. Hapa unawapa wafanyakazi ruhusa, kwa muda au kudumu, na kuziondoa wakati wowote.',
                    style: TextStyle(color: mutedText, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  if (staff.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 32), child: Text('Hakuna wafanyakazi bado.', textAlign: TextAlign.center)),
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
                                Expanded(child: Text('${s['name']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                                const Icon(Icons.chevron_right),
                              ]),
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
      ('Leo tu (hadi saa 5:59 usiku)', endOfToday),
      ('Siku 3', endOfToday.add(const Duration(days: 3))),
      ('Wiki 1', endOfToday.add(const Duration(days: 7))),
      ('Mwezi 1', endOfToday.add(const Duration(days: 30))),
      ('Kudumu (hadi niiondoe)', null),
    ];
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: cardColor,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('$what: mpaka lini?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          for (var i = 0; i < options.length; i++)
            ListTile(
              leading: Icon(options[i].$2 == null ? Icons.all_inclusive : Icons.schedule),
              title: Text(options[i].$1),
              subtitle: options[i].$2 == null ? null : Text('Inaisha ${_until(options[i].$2!.toIso8601String())}'),
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
        until == null ? '$label: imetolewa.' : '$label: imetolewa hadi ${_until(until.toIso8601String())}.',
      );
    } else {
      await _run(() => _api.delete('staff/${widget.staffId}/grants/$key'), '$label: imeondolewa.');
    }
  }

  Future<void> _bundle(Map<String, dynamic> b) async {
    final (ok, until) = await _askUntil('${b['label']}');
    if (!ok) return;
    await _run(
      () => _api.post('staff/${widget.staffId}/bundle', {'bundle': b['key'], 'expires_at': until?.toUtc().toIso8601String()}),
      'Sasa ni ${b['label']}.',
    );
  }

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
            const Text('Historia ya ruhusa', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final r in rows)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(r['active'] == true ? Icons.check_circle : Icons.remove_circle_outline,
                    color: r['active'] == true ? brandGreen : mutedText),
                title: Text('${r['label']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([
                  'Imetolewa ${_until('${r['granted_at']}')}${r['granted_by'] == null ? ' (mwanzo)' : ' na ${r['granted_by']}'}',
                  if (r['expires_at'] != null) 'Hadi ${_until('${r['expires_at']}')}',
                  if (r['revoked_at'] != null) 'Imeondolewa ${_until('${r['revoked_at']}')} na ${r['revoked_by']}',
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
        actions: [IconButton(tooltip: 'Historia', onPressed: _history, icon: const Icon(Icons.history))],
      ),
      body: AbsorbPointer(
        absorbing: _busy, // one change at a time
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            const Text('Weka kwa haraka', style: TextStyle(color: mutedText)),
            const SizedBox(height: 8),
            Row(children: [
              for (final b in bundles)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: () => _bundle(b),
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
                            ? '${c['description']}\nHadi ${_until(active[c['key']]!)}'
                            : '${c['description']}',
                        style: TextStyle(fontSize: 12, color: active[c['key']] != null ? warnAmber : mutedText),
                      ),
                      onChanged: (on) => _toggle('${c['key']}', '${c['label']}', on),
                    ),
                ]),
              ),
            ],
            const Text(
              'Ruhusa ya kusimamia wafanyakazi na ruhusa ni ya mmiliki peke yake; haiwezi kutolewa.',
              style: TextStyle(color: mutedText, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
