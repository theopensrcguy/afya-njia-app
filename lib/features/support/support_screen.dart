import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';

/// Msaada: ask Saola for help, and read the answers.
///
/// The owner sees every request of the shop; staff see their own. Saola's
/// replies come here, and by SMS. Same rules as the web (App\Services\Saola\SupportDesk).
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.session});

  final Session session;

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
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await _api.get('support') as Map<String, dynamic>;
      if (mounted) setState(() => _tickets = (d['tickets'] as List).cast<Map<String, dynamic>>());
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Msaada')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _new,
        icon: const Icon(Icons.add_comment_outlined),
        label: const T('Omba msaada'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 96), children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: T('Una swali au tatizo na Afya Njia? Waandikie Saola hapa. Jibu litakuja hapa, na kwa SMS.',
                      style: TextStyle(color: mutedText)),
                ),
                if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
                if (_tickets.isEmpty && _error == null)
                  const Padding(padding: EdgeInsets.all(32), child: T('Hujaomba msaada bado.', textAlign: TextAlign.center)),
                for (final t in _tickets)
                  Card(
                    color: Colors.white,
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () => _open(t['id'] as int),
                      title: Text('#${t['id']} · ${t['subject']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          _statusPill(t),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              [t['opened_by'], if (t['last_message_at'] != null) timeAgo(DateTime.parse('${t['last_message_at']}').toLocal())]
                                  .whereType<String>()
                                  .join(' · '),
                              style: const TextStyle(color: mutedText, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  ),
              ]),
            ),
    );
  }
}

/// Write to Saola: what it's about, and what happened.
class NewSupportScreen extends StatefulWidget {
  const NewSupportScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<NewSupportScreen> createState() => _NewSupportScreenState();
}

class _NewSupportScreenState extends State<NewSupportScreen> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = tr('Jaza kuhusu nini, na eleza tatizo.'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final t = await widget.api.post('support', {'subject': _subject.text.trim(), 'body': _body.text.trim()}) as Map<String, dynamic>;
      if (mounted) Navigator.of(context).pop(t['id'] as int);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Omba msaada')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
          controller: _subject,
          maxLength: 150,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Kuhusu nini?'), hintText: tr('mfano Siwezi kuingiza mzigo')),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _body,
          minLines: 5,
          maxLines: 10,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: tr('Eleza tatizo'),
            hintText: tr('Ulikuwa unafanya nini, nini kilitokea, na ujumbe gani ulionekana.'),
            alignLabelWithHint: true,
          ),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: dangerRed))),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: const Icon(Icons.send_rounded),
          label: Text(_sending ? tr('Inatuma…') : tr('Tuma kwa Saola')),
        ),
        const SizedBox(height: 12),
        const T('Usiandike PIN yako wala namba za siri. Saola hawatakuuliza PIN kamwe.', style: TextStyle(color: mutedText, fontSize: 12)),
      ]),
    );
  }
}

/// One request: the conversation, a reply box, and "Funga ombi".
class SupportTicketScreen extends StatefulWidget {
  const SupportTicketScreen({super.key, required this.session, required this.id});

  final Session session;
  final int id;

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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: Text(t == null ? tr('Msaada') : '#${t['id']}'),
        actions: [
          if (t != null && t['status'] != 'closed') TextButton(onPressed: _close, child: const T('Funga ombi')),
        ],
      ),
      body: t == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
                    Text('${t['subject']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Row(children: [_statusPill(t)]),
                    const SizedBox(height: 14),
                    for (final m in (t['messages'] as List).cast<Map<String, dynamic>>()) _bubble(m),
                  ]),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: TextField(
                        controller: _reply,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: t['status'] == 'closed' ? tr('Ukituma ujumbe, ombi litafunguliwa tena.') : tr('Ongeza ujumbe'),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                      tooltip: tr('Tuma'),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }

  /// Saola on the left in green; the shop's own messages on the right.
  Widget _bubble(Map<String, dynamic> m) {
    final saola = m['from_saola'] == true;
    final at = m['at'] == null ? '' : timeAgo(DateTime.parse('${m['at']}').toLocal());
    return Align(
      alignment: saola ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: saola ? primarySoft : Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${m['author']} · $at',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: saola ? primaryStrong : mutedText)),
          const SizedBox(height: 4),
          Text('${m['body']}'),
        ]),
      ),
    );
  }
}
