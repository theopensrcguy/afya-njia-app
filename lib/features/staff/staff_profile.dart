import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/i18n.dart';

/// Personal details of staff, built to protect them as much as the shop:
/// optional, owner-only, encrypted on the server, NIDA masked (seeing it needs
/// the owner's PIN and is logged), visible to the person themselves, and
/// erasable after they leave.

const _actions = {
  'updated': 'Taarifa zilihifadhiwa / kubadilishwa',
  'nida_revealed': 'NIDA kamili ilionyeshwa',
  'erased': 'Taarifa binafsi zilifutwa',
};

String _date(String? iso) {
  if (iso == null) return '';
  final d = DateTime.parse(iso).toLocal();
  return '${swahiliDate(d)} ${formatTime(d)}';
}

Widget _row(String label, String? value) => value == null || value.isEmpty
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: mutedText)),
          SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

Widget _accessLog(List log) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(top: 14, bottom: 4),
        child: T('Nani ameangalia au kubadilisha', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      if (log.isEmpty) const T('Hakuna bado.', style: TextStyle(color: mutedText)),
      for (final r in log.cast<Map<String, dynamic>>())
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('• ${_actions[r['action']] == null ? r['action'] : tr(_actions[r['action']]!)} · ${r['by'] ?? ''} · ${_date(r['at'] as String?)}',
              style: const TextStyle(fontSize: 12, color: mutedText)),
        ),
    ]);

// ---------------------------------------------------------------- owner card

/// On a staff member's page (owner only). Loads itself.
class StaffProfileCard extends StatefulWidget {
  const StaffProfileCard({super.key, required this.api, required this.staffId, required this.active});

  final ApiClient api;
  final int staffId;
  final bool active;

  @override
  State<StaffProfileCard> createState() => _StaffProfileCardState();
}

class _StaffProfileCardState extends State<StaffProfileCard> {
  Map<String, dynamic>? _p;
  bool _showLog = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await widget.api.get('staff/${widget.staffId}/profile') as Map<String, dynamic>;
      if (mounted) setState(() => _p = p);
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? dangerRed : null));
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => StaffProfileFormScreen(api: widget.api, staffId: widget.staffId, current: _p!),
    ));
    if (saved == true) _load();
  }

  /// Full NIDA: the owner's own PIN again; logged where the person can see it.
  Future<void> _reveal() async {
    final pin = await showDialog<String>(context: context, builder: (_) => const _OwnerPinDialog());
    if (pin == null || !mounted) return;
    try {
      final res = await widget.api.post('staff/${widget.staffId}/profile/nida', {'pin': pin}) as Map<String, dynamic>;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const T('NIDA kamili'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText('${res['nida']}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1)),
            const SizedBox(height: 10),
            const T('Kuangalia huku kumeandikwa, na mfanyakazi anaweza kukiona kwenye "Taarifa zangu".',
                style: TextStyle(fontSize: 12, color: mutedText)),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.of(d).pop(), child: const T('Funga'))],
        ),
      );
      _load(); // the log now shows this
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _erase() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const T('Futa taarifa binafsi?'),
        content: const T('Simu, mtu wa dharura, makazi, NIDA na maelezo yatafutwa kabisa. Jina lake linabaki kwenye mauzo na historia. Haiwezi kurudishwa.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const T('Ghairi')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: dangerRed),
            onPressed: () => Navigator.of(d).pop(true),
            child: const T('Futa'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final p = await widget.api.delete('staff/${widget.staffId}/profile') as Map<String, dynamic>;
      if (mounted) setState(() => _p = p);
      _toast(tr('Taarifa binafsi zimefutwa.'));
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final empty = p == null || p['consent_at'] == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: softCard(radius: 20),
      child: p == null
          ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.lock_outline, size: 18, color: brandGreen),
                const SizedBox(width: 6),
                const Expanded(child: T('Taarifa binafsi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                if (widget.active) TextButton(onPressed: _edit, child: Text(empty ? tr('Ongeza') : tr('Hariri'))),
              ]),
              if (p['erased_at'] != null)
                Text(tr('Zilifutwa :a.', {'a': _date(p['erased_at'] as String?)}), style: const TextStyle(color: mutedText))
              else if (empty)
                const T('Hakuna taarifa. Ni hiari: simu, mtu wa dharura, makazi, NIDA.', style: TextStyle(color: mutedText))
              else ...[
                _row(tr('Simu'), p['phone'] as String?),
                _row(tr('Mtu wa dharura'),
                    [p['emergency_name'], p['emergency_relation'], p['emergency_phone']].where((v) => v != null && '$v'.isNotEmpty).join(' · ')),
                _row(tr('Makazi (mtaa / kata)'), p['residence_area'] as String?),
                _row(tr('Alianza kazi'), p['started_on'] == null ? null : swahiliDate(DateTime.parse('${p['started_on']}'))),
                if (p['nida_masked'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p['nida_verified_at'] != null ? tr('NIDA · imethibitishwa') : tr('NIDA'),
                              style: const TextStyle(fontSize: 12, color: mutedText)),
                          Text('${p['nida_masked']}', style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1)),
                        ]),
                      ),
                      TextButton.icon(onPressed: _reveal, icon: const Icon(Icons.visibility_outlined, size: 18), label: const T('Onyesha')),
                    ]),
                  ),
                _row(tr('Maelezo (wewe tu)'), p['notes'] as String?),
                _row(tr('Ridhaa ya mfanyakazi'), _date(p['consent_at'] as String?)),
              ],
              TextButton(
                onPressed: () => setState(() => _showLog = !_showLog),
                child: Text(_showLog ? tr('Ficha kumbukumbu') : tr('Nani ameangalia?')),
              ),
              if (_showLog) _accessLog((p['access_log'] as List?) ?? const []),
              if (!widget.active && p['erased_at'] == null && !empty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: _erase,
                    icon: const Icon(Icons.delete_forever_outlined, color: dangerRed),
                    label: const T('Futa taarifa binafsi', style: TextStyle(color: dangerRed)),
                  ),
                ),
            ]),
    );
  }
}

class _OwnerPinDialog extends StatefulWidget {
  const _OwnerPinDialog();

  @override
  State<_OwnerPinDialog> createState() => _OwnerPinDialogState();
}

class _OwnerPinDialogState extends State<_OwnerPinDialog> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const T('Weka PIN yako'),
      content: TextField(
        controller: _pin,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
        style: const TextStyle(fontSize: 22, letterSpacing: 10, fontWeight: FontWeight.w800),
        onChanged: (v) {
          if (v.length == 4) Navigator.of(context).pop(v);
        },
        decoration: InputDecoration(helperText: tr('Kuona NIDA kamili kunaandikwa kwenye kumbukumbu.')),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const T('Ghairi'))],
    );
  }
}

// ---------------------------------------------------------------- owner form

class StaffProfileFormScreen extends StatefulWidget {
  const StaffProfileFormScreen({super.key, required this.api, required this.staffId, required this.current});

  final ApiClient api;
  final int staffId;
  final Map<String, dynamic> current;

  @override
  State<StaffProfileFormScreen> createState() => _StaffProfileFormScreenState();
}

class _StaffProfileFormScreenState extends State<StaffProfileFormScreen> {
  late final _fields = {
    for (final k in const ['phone', 'emergency_name', 'emergency_relation', 'emergency_phone', 'residence_area', 'notes'])
      k: TextEditingController(text: '${widget.current[k] ?? ''}'),
  };
  final _nida = TextEditingController();
  late DateTime? _started = widget.current['started_on'] == null ? null : DateTime.parse('${widget.current['started_on']}');
  late bool _verified = widget.current['nida_verified_at'] != null;
  late final bool _hadConsent = widget.current['consent_at'] != null;
  bool _consent = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _nida.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_hadConsent && !_consent) {
      setState(() => _error = tr('Kwanza thibitisha kwamba mfanyakazi amekubali.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.put('staff/${widget.staffId}/profile', {
        if (!_hadConsent) 'consent': true,
        for (final e in _fields.entries) e.key: e.value.text.trim(),
        'started_on': _started?.toIso8601String().substring(0, 10),
        // Empty = keep the NIDA already saved (it's never sent back to the phone).
        if (_nida.text.trim().isNotEmpty) 'nida': _nida.text.trim(),
        'nida_verified': _verified,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, {TextInputType? type, String? hint, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _fields[key],
          keyboardType: type,
          maxLines: lines,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final masked = widget.current['nida_masked'] as String?;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Taarifa za :a', {'a': widget.current['name']})), backgroundColor: pageBackground),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const T('Zote ni za hiari. Zinahifadhiwa kwa usimbaji fiche, na wewe pekee ndiye unaziona. Mfanyakazi anaweza kuona taarifa zake mwenyewe.',
              style: TextStyle(color: mutedText, fontSize: 13)),
          const SizedBox(height: 16),
          _field('phone', tr('Simu'), type: TextInputType.phone, hint: tr('07xx xxx xxx')),
          const T('Mtu wa kuwasiliana naye kwa dharura', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _field('emergency_name', tr('Jina')),
          _field('emergency_relation', tr('Uhusiano'), hint: tr('mf. Mama, Kaka, Mume')),
          _field('emergency_phone', tr('Simu yake'), type: TextInputType.phone),
          _field('residence_area', tr('Makazi: mtaa / kata'), hint: tr('mf. Sinza, Kinondoni (si anwani kamili)')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const T('Alianza kazi'),
            subtitle: Text(_started == null ? tr('Chagua tarehe') : swahiliDate(_started!)),
            trailing: const Icon(Icons.event_outlined),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _started ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => _started = d);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nida,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(20)],
            decoration: InputDecoration(
              labelText: masked == null ? tr('NIDA (tarakimu 20)') : tr('NIDA mpya (acha wazi kubaki na :masked)', {'masked': masked}),
              counterText: '',
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _verified,
            onChanged: (v) => setState(() => _verified = v ?? false),
            title: const T('Nimeona kitambulisho chake na kulinganisha'),
          ),
          _field('notes', tr('Maelezo (wewe tu unayaona)'), lines: 3),
          if (!_hadConsent)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              title: const T('Mfanyakazi amekubali taarifa hizi zihifadhiwe'),
              subtitle: const T('Anaweza kuziona kwenye "Taarifa zangu".'),
            ),
          if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            child: Text(_saving ? tr('Inahifadhi…') : tr('Hifadhi')),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- my own view

/// "Taarifa zangu": what the shop keeps about me, and who looked at it.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key, required this.session});

  final Session session;

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  Map<String, dynamic>? _p;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.session.api.get('me/profile').then((p) {
      if (mounted) setState(() => _p = p as Map<String, dynamic>);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(title: const T('Taarifa zangu'), backgroundColor: pageBackground),
      body: p == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                const T('Hizi ndizo taarifa ambazo duka limehifadhi kukuhusu. Kama kuna kosa, mwambie mmiliki.',
                    style: TextStyle(color: mutedText, fontSize: 13)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: softCard(radius: 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p['name']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    if (p['consent_at'] == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: T('Hakuna taarifa binafsi zilizohifadhiwa.', style: TextStyle(color: mutedText)),
                      ),
                    _row(tr('Simu'), p['phone'] as String?),
                    _row(tr('Mtu wa dharura'),
                        [p['emergency_name'], p['emergency_relation'], p['emergency_phone']].where((v) => v != null && '$v'.isNotEmpty).join(' · ')),
                    _row(tr('Makazi'), p['residence_area'] as String?),
                    _row(tr('Alianza kazi'), p['started_on'] == null ? null : swahiliDate(DateTime.parse('${p['started_on']}'))),
                    _row(tr('NIDA'), p['nida_masked'] as String?),
                    _row(tr('Ulikubali'), _date(p['consent_at'] as String?)),
                    _accessLog((p['access_log'] as List?) ?? const []),
                  ]),
                ),
              ],
            ),
    );
  }
}
