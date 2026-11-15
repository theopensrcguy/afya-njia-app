import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/loader.dart';
import '../../core/session.dart';
import '../../core/units.dart';
import '../../models/product.dart';

/// Ask to delete a product (with all its stock) or one batch recorded by
/// mistake. Someone allowed to approve deletes at once; anyone else's
/// request waits. Returns true when something was sent or deleted.
Future<bool> askDeleteStock(
  BuildContext context, {
  required ApiClient api,
  required bool canApprove,
  required int productId,
  required String productName,
  Map<String, dynamic>? batch,
  String? quantityText,
}) async {
  final what = batch == null ? productName : tr('batch :b ya :name', {'b': batch['batch_number'], 'name': productName});
  final reason = await askText(
    context,
    title: canApprove ? tr('Futa :what', {'what': what}) : tr('Omba kufuta :what', {'what': what}),
    label: tr('Sababu'),
    hint: tr('mfano Imeingizwa mara mbili kwa makosa'),
    danger: true,
    confirm: canApprove ? tr('Futa') : tr('Tuma ombi'),
    message: [
      batch == null
          ? tr('Bidhaa itaondoka kwenye orodha na hisa yake yote itaondolewa. Mauzo yake ya zamani na ripoti zinabaki.')
          : tr('Hisa ya batch hii (:n) itaondolewa.', {'n': quantityText ?? ''}),
      canApprove ? tr('Itafutwa sasa hivi.') : tr('Haitafutwa mpaka mwenye ruhusa aidhinishe.'),
    ].join(' '),
    required: true,
  );
  if (reason == null || reason.trim().length < 3 || !context.mounted) return false;
  try {
    final r = await api.post('stock-deletions', {'product_id': productId, 'batch_id': batch?['id'], 'reason': reason.trim()}) as Map<String, dynamic>;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['status'] == 'approved' ? tr('Imefutwa.') : tr('Ombi limetumwa. Litafutwa likiidhinishwa.')),
      ));
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// "Maombi ya kufuta": requests to delete stock. Approvers see everyone's and
/// approve or decline; others see their own and can take them back.
class DeletionsScreen extends StatefulWidget {
  const DeletionsScreen({super.key, required this.session});

  final Session session;

  @override
  State<DeletionsScreen> createState() => _DeletionsScreenState();
}

class _DeletionsScreenState extends State<DeletionsScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _canApprove = false;
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.get('stock-deletions') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _canApprove = r['can_approve'] == true;
        _list = (r['requests'] as List).cast<Map<String, dynamic>>();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Future<dynamic> Function() call, String done) async {
    try {
      await call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _approve(Map<String, dynamic> d) async {
    final ok = await confirmDialog(context,
        title: tr('Futa :what', {'what': d['product']}),
        message: tr('Futa :what? Hisa yake itaondolewa (historia inabaki).', {'what': d['product']}),
        confirm: tr('Ndiyo, futa'),
        danger: true);
    if (ok != true) return;
    await _act(() => _api.post('stock-deletions/${d['id']}/approve'), tr('Imefutwa.'));
  }

  Future<void> _decline(Map<String, dynamic> d) async {
    final note = await askText(context, title: tr('Kataa ombi la kufuta'), label: tr('Sababu (si lazima)'));
    if (note == null) return;
    await _act(() => _api.post('stock-deletions/${d['id']}/decline', {'note': note.trim().isEmpty ? null : note.trim()}), tr('Ombi limekataliwa.'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          T(_canApprove ? 'Maombi ya kufuta hisa' : 'Maombi yako ya kufuta', style: const TextStyle(fontWeight: FontWeight.w800)),
          T(_canApprove ? 'Hakuna kinachofutwa mpaka uidhinishe.' : 'Yanasubiri idhini ya mmiliki.', style: const TextStyle(fontSize: 12, color: mutedText)),
        ]),
      ),
      body: _loading
          ? const Center(child: AfyaLoader())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
                if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
                if (_list.isEmpty && _error == null)
                  const Padding(padding: EdgeInsets.all(32), child: T('Hakuna ombi linalosubiri.', textAlign: TextAlign.center, style: TextStyle(color: mutedText))),
                for (final d in _list) _card(d),
              ]),
            ),
    );
  }

  Widget _card(Map<String, dynamic> d) {
    final units = ((d['units'] as List?) ?? const []).cast<Map<String, dynamic>>().map(ProductUnit.fromJson).toList();
    final at = DateTime.tryParse('${d['created_at'] ?? ''}');
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: softCard(radius: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${d['product']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        Text(
          d['kind'] == 'batch' ? tr('Batch :b', {'b': d['batch_number']}) : tr('Bidhaa yote (na hisa yake)'),
          style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w700),
        ),
        Text('${describeStock(asInt(d['quantity']), units)} · ${d['reason']}'),
        Text('${d['requested_by']}${at == null ? '' : ' · ${timeAgo(at)}'}', style: const TextStyle(fontSize: 12, color: mutedText)),
        const SizedBox(height: 10),
        if (_canApprove)
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _decline(d), child: const T('Kataa'))),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => _approve(d),
                style: FilledButton.styleFrom(backgroundColor: dangerRed),
                child: const T('Idhinisha'),
              ),
            ),
          ])
        else
          OutlinedButton(
            onPressed: () => _act(() => _api.delete('stock-deletions/${d['id']}'), tr('Ombi limeghairiwa.')),
            child: const T('Ghairi ombi'),
          ),
      ]),
    );
  }
}
