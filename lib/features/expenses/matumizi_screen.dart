import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';

/// Matumizi: money the shop spends on things other than stock (rent, power,
/// wages…). Five starter types, plus the shop's own. Cash spent today comes
/// off the open shift's drawer (the server ties it to the shift).
class MatumiziScreen extends StatefulWidget {
  const MatumiziScreen({super.key, required this.session});

  final Session session;

  @override
  State<MatumiziScreen> createState() => _MatumiziScreenState();
}

const _methods = ['cash', 'mobile', 'bank'];
String _methodLabel(String m) => switch (m) { 'cash' => tr('Taslimu'), 'mobile' => tr('Simu'), 'bank' => tr('Benki'), _ => m };
String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _MatumiziScreenState extends State<MatumiziScreen> {
  String _range = 'month'; // today | month | last
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _categories = [];
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (String, String) get _bounds {
    final now = DateTime.now();
    return switch (_range) {
      'today' => (_iso(now), _iso(now)),
      'last' => (_iso(DateTime(now.year, now.month - 1, 1)), _iso(DateTime(now.year, now.month, 0))),
      _ => (_iso(DateTime(now.year, now.month, 1)), _iso(now)),
    };
  }

  Future<void> _load() async {
    final (from, to) = _bounds;
    try {
      final results = await Future.wait([
        _api.get('expenses', query: {'from': from, 'to': to}),
        _api.get('expense-categories'),
      ]);
      if (!mounted) return;
      setState(() {
        _data = results[0] as Map<String, dynamic>;
        _categories = (results[1] as List).cast<Map<String, dynamic>>();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String text, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? dangerRed : null));
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _AddExpenseScreen(api: _api, categories: _categories)),
    );
    if (saved == true) {
      _toast(tr('Matumizi yamehifadhiwa.'));
      _load();
    }
  }

  Future<void> _void(Map<String, dynamic> e) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const T('Futa matumizi haya?'),
        content: TextField(controller: reason, decoration: InputDecoration(labelText: tr('Sababu'))),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const T('Ghairi')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), style: FilledButton.styleFrom(backgroundColor: dangerRed), child: const T('Futa')),
        ],
      ),
    );
    if (ok != true || reason.text.trim().isEmpty) return;
    try {
      await _api.post('expenses/${e['id']}/void', {'reason': reason.text.trim()});
      _toast(tr('Yamefutwa.'));
      _load();
    } on ApiException catch (ex) {
      _toast(ex.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final me = widget.session.user!;
    final today = _iso(DateTime.now());
    return Scaffold(
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Matumizi')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const T('Ongeza matumizi')),
      body: d == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                Wrap(spacing: 8, children: [
                  for (final (k, label) in [('today', tr('Leo')), ('month', tr('Mwezi huu')), ('last', tr('Mwezi uliopita'))])
                    ChoiceChip(label: Text(label), selected: _range == k, onSelected: (_) {
                      setState(() => _range = k);
                      _load();
                    }),
                ]),
                const SizedBox(height: 8),
                Card(
                  color: Colors.white,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const T('Jumla', style: TextStyle(color: mutedText)),
                      Text(formatTsh((d['total'] as num).toInt()), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      for (final c in (d['by_category'] as List).cast<Map<String, dynamic>>())
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            Expanded(child: Text(tr('${c['name']}'))),
                            Text(formatTsh((c['total'] as num).toInt()), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ]),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                if ((d['expenses'] as List).isEmpty)
                  const Padding(padding: EdgeInsets.all(32), child: T('Hakuna matumizi kipindi hiki.', textAlign: TextAlign.center, style: TextStyle(color: mutedText))),
                for (final e in (d['expenses'] as List).cast<Map<String, dynamic>>())
                  Opacity(
                    opacity: e['voided'] == true ? 0.5 : 1,
                    child: Card(
                      color: Colors.white,
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('${(e['category'] as Map?)?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([
                          '${e['spent_on']}',
                          _methodLabel('${e['method']}'),
                          if ((e['note'] ?? '').toString().isNotEmpty) '${e['note']}',
                          if (e['voided'] == true) '${tr('Imefutwa')}: ${e['void_reason'] ?? ''}',
                        ].join(' · ')),
                        trailing: Text(formatTsh((e['amount'] as num).toInt()),
                            style: TextStyle(fontWeight: FontWeight.w800, decoration: e['voided'] == true ? TextDecoration.lineThrough : null)),
                        // Void: the owner (with costs) any time; the person who wrote it, the same day.
                        onLongPress: e['voided'] != true && (me.can(Perm.viewCosts) || (e['user_id'] == me.id && e['spent_on'] == today)) ? () => _void(e) : null,
                      ),
                    ),
                  ),
                if ((d['expenses'] as List).isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: T('Bonyeza kwa muda mrefu kufuta uliyokosea.', textAlign: TextAlign.center, style: TextStyle(color: mutedText, fontSize: 12)),
                  ),
              ]),
            ),
    );
  }
}

class _AddExpenseScreen extends StatefulWidget {
  const _AddExpenseScreen({required this.api, required this.categories});

  final ApiClient api;
  final List<Map<String, dynamic>> categories;

  @override
  State<_AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<_AddExpenseScreen> {
  late List<Map<String, dynamic>> _cats = [...widget.categories];
  int? _cat;
  String _method = 'cash';
  DateTime _day = DateTime.now();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cat = _cats.isEmpty ? null : _cats.first['id'] as int;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _newCategory() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const T('Aina mpya ya matumizi'),
        content: TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Jina'), hintText: tr('mfano Mafuta ya jenereta'))),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const T('Ghairi')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const T('Hifadhi')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final c = await widget.api.post('expense-categories', {'name': name.text.trim()}) as Map<String, dynamic>;
      setState(() {
        if (!_cats.any((x) => x['id'] == c['id'])) _cats = [..._cats, c];
        _cat = c['id'] as int;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amount.text) ?? 0;
    if (_cat == null || amount <= 0) {
      setState(() => _error = tr('Chagua aina na weka kiasi.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.post('expenses', {
        'expense_category_id': _cat,
        'amount': amount,
        'method': _method,
        'spent_on': _iso(_day),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Ongeza matumizi')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const T('Aina', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in _cats)
            ChoiceChip(label: Text(tr('${c['name']}')), selected: _cat == c['id'], onSelected: (_) => setState(() => _cat = c['id'] as int)),
          ActionChip(avatar: const Icon(Icons.add, size: 18), label: const T('Aina mpya'), onPressed: _newCategory),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: tr('Kiasi (TSh)')),
        ),
        const SizedBox(height: 16),
        const T('Imelipwa kwa', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [for (final m in _methods) ButtonSegment(value: m, label: Text(_methodLabel(m)))],
          selected: {_method},
          onSelectionChanged: (s) => setState(() => _method = s.first),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(_iso(_day)),
          subtitle: const T('Tarehe'),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now());
            if (d != null) setState(() => _day = d);
          },
        ),
        TextField(controller: _note, maxLength: 255, decoration: InputDecoration(labelText: tr('Maelezo (si lazima)'), hintText: tr('mfano Kodi ya Desemba'))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: const TextStyle(color: dangerRed))),
        const SizedBox(height: 12),
        FilledButton(onPressed: _saving ? null : _save, child: const T('Hifadhi')),
      ]),
    );
  }
}
