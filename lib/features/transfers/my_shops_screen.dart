import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/i18n.dart';
import '../../core/loader.dart';
import '../../core/session.dart';

/// "Maduka yangu": every shop this person is in, with one number and one PIN
/// (owner in one, worker in another…). Tap one to open it on this phone
/// without signing out. Owners can bring a shop of theirs that was registered
/// under another number onto this one (its code and its owner's PIN).
class MyShopsScreen extends StatefulWidget {
  const MyShopsScreen({super.key, required this.session});

  final Session session;

  @override
  State<MyShopsScreen> createState() => _MyShopsScreenState();
}

class _MyShopsScreenState extends State<MyShopsScreen> {
  List<Map<String, dynamic>>? _shops;
  String? _error;
  bool _busy = false;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get('my-shops') as Map<String, dynamic>;
      if (mounted) setState(() => _shops = (r['shops'] as List).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _switch(Map<String, dynamic> s) async {
    setState(() => _busy = true);
    try {
      final nav = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      await widget.session.switchShop((s['user_id'] as num).toInt());
      // The whole app now belongs to that shop: back to its home screen.
      nav.popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(content: Text(tr('Sasa uko :shop.', {'shop': s['name']}))));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final added = await showDialog<bool>(context: context, builder: (_) => _AddShopDialog(api: _api));
    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Duka limeongezwa kwenye maduka yako.'))));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Maduka yangu', style: TextStyle(fontWeight: FontWeight.w800))),
      body: _shops == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: dangerRed)) : const AfyaLoader())
          : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
              const T('Maduka yote yaliyosajiliwa kwa namba yako. Unaingia mara moja kwa PIN yako, kisha unabadili duka bila kutoka.', style: TextStyle(color: mutedText)),
              const SizedBox(height: 12),
              for (final s in _shops!)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: softCard(radius: 18),
                  child: ListTile(
                    leading: Icon(Icons.storefront_rounded, color: s['current'] == true ? brandGreen : mutedText),
                    title: Text('${s['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text([
                      if (s['location'] != null) '${s['location']}',
                      if (s['role'] == 'helper') tr('mfanyakazi') else '${s['shop_code']}',
                    ].join(' · ')),
                    trailing: s['current'] == true
                        ? T('uko hapa', style: const TextStyle(color: brandGreen, fontWeight: FontWeight.w800))
                        : FilledButton(onPressed: _busy ? null : () => _switch(s), child: const T('Fungua')),
                  ),
                ),
              if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
              if (widget.session.user!.isOwner) ...[
                OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add_business_outlined), label: const T('Ongeza duka langu jingine')),
                const SizedBox(height: 6),
                const T('Duka jipya linalosajiliwa na Saola kwa namba yako linaongezwa hapa lenyewe. Hiki ni kwa duka lako lililosajiliwa kwa namba nyingine.',
                    style: TextStyle(color: mutedText, fontSize: 12)),
              ],
            ]),
    );
  }
}

class _AddShopDialog extends StatefulWidget {
  const _AddShopDialog({required this.api});

  final ApiClient api;

  @override
  State<_AddShopDialog> createState() => _AddShopDialogState();
}

class _AddShopDialogState extends State<_AddShopDialog> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('my-shops', {'shop_code': _code.text.trim(), 'pin': _pin.text.trim()});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const T('Ongeza duka langu jingine'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const T('Duka lako lililosajiliwa kwa namba nyingine. Kuthibitisha ni lako: namba ya duka hilo na PIN ya mmiliki wake. Litahamia namba yako na PIN yako; namba ile nyingine itaachwa huru. Maduka yako yataweza kuhamishiana hisa moja kwa moja.',
              style: TextStyle(fontSize: 13, color: mutedText)),
          TextField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: tr('Namba ya duka'))),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: InputDecoration(labelText: tr('PIN ya mmiliki wa duka hilo')),
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const T('Ghairi')),
        FilledButton(onPressed: _busy ? null : _save, child: const T('Ongeza')),
      ],
    );
  }
}
