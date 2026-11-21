import 'package:flutter/material.dart';

import '../../core/loader.dart';
import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/session.dart';
import '../../core/i18n.dart';
import '../../core/format.dart';
import '../../core/smooth.dart';

/// Owner only: phones allowed to use the pharmacy.
///
/// Waiting phones are on top with their 6-digit number. The owner checks it
/// matches what the helper's phone shows, then approves. Approved phones can
/// be removed; access stops on that phone immediately.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.session});

  final Session session;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;
  String? _error;
  int? _busyId; // the device being approved/removed, to show a spinner on its row

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await _api.get('devices') as List<dynamic>;
      if (!mounted) return;
      setState(() => _devices = data.cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setMode(Map<String, dynamic> device, bool shared) async {
    setState(() => _busyId = device['id']);
    try {
      await widget.session.api.patch('devices/${device['id']}/mode', {'mode': shared ? 'shared' : 'personal'});
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _approve(Map<String, dynamic> device) async {
    await _act(device, 'approve', tr('Kifaa kimeidhinishwa.'));
  }

  Future<void> _revoke(Map<String, dynamic> device, {bool refuse = false}) async {
    // Removing is serious: confirm first. Refusing a waiting device is the same call.
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: T(refuse ? 'Kataa kifaa hiki?' : 'Ondoa kifaa hiki?'),
        content: Text(tr(':a hakitaweza kutumia Afya Njia tena. Kitahitaji idhini mpya.', {'a': device['name']})),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const T('Hapana')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: dangerRed),
            onPressed: () => Navigator.of(context).pop(true),
            child: T(refuse ? 'Kataa' : 'Ondoa'),
          ),
        ],
      ),
    );
    if (sure == true) await _act(device, 'revoke', refuse ? tr('Kifaa kimekataliwa.') : tr('Kifaa kimeondolewa.'));
  }

  Future<void> _act(Map<String, dynamic> device, String action, String doneMessage) async {
    final id = device['id'] as int;
    setState(() => _busyId = id);
    try {
      await _api.post('devices/$id/$action');
      _snack(doneMessage);
      await _load();
    } on ApiException catch (e) {
      _snack(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _snack(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: isError ? dangerRed : null));
  }

  @override
  Widget build(BuildContext context) {
    final waiting = _devices.where((d) => d['status'] == 'pending').toList();
    final approved = _devices.where((d) => d['status'] == 'approved').toList();
    final removed = _devices.where((d) => d['status'] != 'pending' && d['status'] != 'approved').toList();
    final me = approved.where((d) => d['is_this_device'] == true).firstOrNull;
    final others = approved.where((d) => d['is_this_device'] != true).toList();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, surfaceTintColor: Colors.transparent, title: const T('Vifaa', style: TextStyle(fontWeight: FontWeight.w800))),
      body: _loading
          ? const Center(child: AfyaLoader())
          : RefreshIndicator(
              // Pull down to refresh: the helper's request appears the moment he types his PIN.
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: staggered([
                  if (_error != null)
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: dangerRed))),
                  _hero(me, approved.length, waiting.length),
                  if (waiting.isNotEmpty) ...[
                    _heading(tr('Vinasubiri idhini'), waiting.length, warnAmber),
                    for (final d in waiting) _waitingCard(d),
                  ],
                  if (others.isNotEmpty) ...[
                    _heading(tr('Vinaruhusiwa'), others.length, brandGreen),
                    for (final d in others) _deviceCard(d),
                  ],
                  if (_devices.isEmpty && _error == null)
                    const Padding(padding: EdgeInsets.only(top: 40), child: T('Hakuna kifaa bado.', textAlign: TextAlign.center, style: TextStyle(color: mutedText))),
                  if (removed.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Container(
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .6), borderRadius: BorderRadius.circular(18)),
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            shape: const RoundedRectangleBorder(),
                            title: Text(tr('Vilivyoondolewa · :n', {'n': removed.length}), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: mutedText)),
                            children: [
                              for (final d in removed)
                                ListTile(
                                  dense: true,
                                  leading: Icon(_iconOf(d), color: const Color(0xFFB8C4C0)),
                                  title: Text('${d['name']}', style: const TextStyle(color: mutedText, decoration: TextDecoration.lineThrough)),
                                  subtitle: Text(tr('Imeombwa na :a', {'a': '${d['requested_by'] ?? ''}'})),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 18, 8, 0),
                    child: T('Kifaa kipya kinasubiri hapa mpaka ukiruhusu. Simu ikipotea, iondoe: inatolewa papo hapo.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: mutedText)),
                  ),
                ]),
              ),
            ),
    );
  }

  static const _bg = Color(0xFFF2F6F4);

  IconData _iconOf(Map<String, dynamic> d) {
    final name = '${d['name']}'.toLowerCase();
    if (name.contains('kivinjari') || name.contains('browser')) return Icons.language_rounded;
    if (d['mode'] == 'shared') return Icons.storefront_outlined;
    return Icons.smartphone_rounded;
  }

  String _seen(Map<String, dynamic> d) {
    final at = DateTime.tryParse('${d['last_used_at']}');
    return [
      if (d['last_user'] != null) '${d['last_user']}',
      if (at != null) timeAgo(at),
    ].join(' · ');
  }

  Widget _heading(String text, int n, Color c) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(children: [
          Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
            child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
          ),
        ]),
      );

  /// Dark card: this phone or browser, and how many are allowed / waiting.
  Widget _hero(Map<String, dynamic>? me, int approved, int waiting) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF0E3B31), borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: const Color(0xFF3DDC97).withValues(alpha: .16), borderRadius: BorderRadius.circular(15)),
              child: Icon(me == null ? Icons.devices_rounded : _iconOf(me), color: const Color(0xFF3DDC97)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(me == null ? tr('Vifaa vya duka') : tr('Kifaa hiki'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                if (me != null)
                  Text('${me['name']} · ${me['mode'] == 'shared' ? tr('Kaunta') : tr('Binafsi')}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFA9C4BA), fontSize: 12.5)),
              ]),
            ),
            if (me != null) _modeSwitch(me, dark: true),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _count(approved, tr('vinaruhusiwa'), Colors.white, Colors.white.withValues(alpha: .08))),
            const SizedBox(width: 10),
            Expanded(
              child: _count(waiting, tr('vinasubiri'), waiting > 0 ? const Color(0xFFF2B36B) : Colors.white70,
                  waiting > 0 ? const Color(0xFFF2B36B).withValues(alpha: .16) : Colors.white.withValues(alpha: .08)),
            ),
          ]),
        ]),
      );

  Widget _count(int n, String label, Color fg, Color bg) => Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          CountUp(value: n, format: (v) => '$v', style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withValues(alpha: .8), fontSize: 12))),
        ]),
      );

  /// Binafsi | Kaunta: what its sign-in screen shows (one person's PIN, or the counter list).
  Widget _modeSwitch(Map<String, dynamic> d, {bool dark = false}) {
    final shared = d['mode'] == 'shared';
    final busy = _busyId == d['id'];
    Widget seg(String label, bool on, bool value) => Expanded(
          child: GestureDetector(
            onTap: busy || on ? null : () => _setMode(d, value),
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.base),
              curve: Motion.curve,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? (dark ? const Color(0xFF3DDC97) : Colors.white) : Colors.transparent,
                borderRadius: BorderRadius.circular(99),
                boxShadow: on && !dark ? [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 6, offset: const Offset(0, 2))] : null,
              ),
              child: Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    color: dark ? (on ? const Color(0xFF0E3B31) : Colors.white70) : (on ? const Color(0xFF14211D) : mutedText),
                  )),
            ),
          ),
        );
    return Opacity(
      opacity: busy ? .5 : 1,
      child: Container(
        width: dark ? 140 : double.infinity,
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: dark ? Colors.white.withValues(alpha: .1) : const Color(0xFFEEF3F1), borderRadius: BorderRadius.circular(99)),
        child: Row(children: [seg(tr('Binafsi'), !shared, false), seg(tr('Kaunta'), shared, true)]),
      ),
    );
  }

  /// A new phone or browser: its 6 digits as boxes, to compare with its screen.
  Widget _waitingCard(Map<String, dynamic> d) {
    final busy = _busyId == d['id'];
    final code = '${d['pairing_code'] ?? ''}';
    final at = DateTime.tryParse('${d['requested_at']}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFF2D9A8))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: warnSoft, borderRadius: BorderRadius.circular(13)),
              child: Icon(_iconOf(d), color: warnAmber, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text([tr('Imeombwa na :a', {'a': '${d['requested_by'] ?? ''}'}), if (at != null) timeAgo(at)].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: mutedText)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          const T('Linganisha na namba zilizo kwenye skrini yake:', style: TextStyle(fontSize: 12.5, color: mutedText)),
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < code.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFF4F8F6), borderRadius: BorderRadius.circular(12)),
                  child: Text(code[i], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: Motion.of(context, Motion.fast),
            child: busy
                ? const SizedBox(height: 46, child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))))
                : Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _revoke(d, refuse: true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: dangerRed,
                          side: const BorderSide(color: Color(0xFFF0C9C1)),
                          shape: const StadiumBorder(),
                          minimumSize: const Size.fromHeight(46),
                        ),
                        child: const T('Kataa'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () => _approve(d),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2F8A6C), shape: const StadiumBorder(), minimumSize: const Size.fromHeight(46)),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const T('Ruhusu'),
                      ),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }

  /// An approved device: icon, who used it last and when, Binafsi | Kaunta, and ⋮ Ondoa.
  Widget _deviceCard(Map<String, dynamic> d) {
    final shared = d['mode'] == 'shared';
    final icon = _iconOf(d);
    final (bg, fg) = icon == Icons.language_rounded
        ? (const Color(0xFFEAF0FD), const Color(0xFF2F5FC4))
        : (shared ? (const Color(0xFFE7F6EF), const Color(0xFF1F8A66)) : (const Color(0xFFEFF4F2), const Color(0xFF0E3B31)));
    final seen = _seen(d);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: fg, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(seen.isEmpty ? tr('Imeombwa na :a', {'a': '${d['requested_by'] ?? ''}'}) : seen,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: mutedText)),
              ]),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: mutedText),
              onSelected: (_) => _revoke(d),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'revoke',
                  child: Row(children: [
                    const Icon(Icons.block_rounded, color: dangerRed, size: 20),
                    const SizedBox(width: 10),
                    Text(tr('Ondoa kifaa'), style: const TextStyle(color: dangerRed)),
                  ]),
                ),
              ],
            ),
          ]),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              Expanded(
                child: Text(shared ? tr('Skrini ya kuingia inaonyesha wanaoitumia') : tr('Inauliza PIN ya :a tu', {'a': d['last_user'] ?? tr('mtumiaji wake')}),
                    maxLines: 2, style: const TextStyle(fontSize: 11.5, color: mutedText)),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 150, child: _modeSwitch(d)),
            ]),
          ),
        ]),
      ),
    );
  }
}
