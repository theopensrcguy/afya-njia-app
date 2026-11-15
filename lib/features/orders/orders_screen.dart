import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/loader.dart';
import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../suppliers/suppliers_screen.dart';
import 'order_send_screen.dart';
import 'reorder_screen.dart';

/// Maagizo: every order the shop made (drafts, sent, delivered, cancelled),
/// with or without a supplier. A draft is finished and sent from here; a sent
/// order can be opened in WhatsApp again, or cancelled ("haitakuja").
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.session, this.status = 'all', this.suppliers = const []});

  final Session session;

  /// all | draft | sent | received | cancelled
  final String status;

  /// To filter by supplier, and to choose one when finishing a draft.
  final List<Map<String, dynamic>> suppliers;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  static const _statuses = [
    ('all', 'Yote'),
    ('draft', 'Rasimu'),
    ('sent', 'Yanasubiri'),
    ('received', 'Yamefika'),
    ('cancelled', 'Yameghairiwa'),
  ];

  late String _status = widget.status;
  String _supplier = ''; // '' = all, 'none' = without a supplier, or an id
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.get('purchase-orders', query: {'status': _status, if (_supplier.isNotEmpty) 'supplier': _supplier}) as List;
      if (mounted) setState(() => _orders = r.cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  (String, Color) _label(String status) => switch (status) {
        'draft' => (tr('Rasimu'), const Color(0xFF2F5FA8)),
        'sent' => (tr('Linasubiriwa'), warnAmber),
        'received' => (tr('Limefika'), brandGreen),
        'cancelled' => (tr('Limeghairiwa'), mutedText),
        _ => (status, mutedText),
      };

  String _when(Map<String, dynamic> o) {
    final at = DateTime.tryParse('${o['sent_at'] ?? o['updated_at'] ?? ''}');
    return at == null ? '' : timeAgo(at);
  }

  // ------------------------------------------------------------- actions

  Future<void> _finishDraft(Map<String, dynamic> o) async {
    final lines = [
      for (final l in ((o['lines'] as List?) ?? const []).cast<Map<String, dynamic>>()) {...l, 'name': l['product']},
    ];
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => OrderSendScreen(
        session: widget.session,
        supplier: o['supplier'] as Map<String, dynamic>?,
        suppliers: widget.suppliers,
        cover: asInt(o['cover_days']) == 0 ? 14 : asInt(o['cover_days']),
        lines: lines,
        orderId: asInt(o['id']),
      ),
    ));
    if (done == true && mounted) _load();
  }

  Future<void> _continueDraft(Map<String, dynamic> o) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReorderScreen(session: widget.session, draftId: asInt(o['id'])),
    ));
    if (mounted) _load();
  }

  Future<void> _post(String path, String done, {bool delete = false}) async {
    try {
      delete ? await _api.delete(path) : await _api.post(path, const {});
      if (!mounted) return;
      _toast(done);
      _load();
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _whatsApp(Map<String, dynamic> o) async {
    final s = o['supplier'] as Map<String, dynamic>?;
    final n = tzNumber((s?['whatsapp_number'] ?? s?['phone']) as String?);
    final uri = Uri.parse('https://wa.me/${n ?? ''}?text=${Uri.encodeComponent('${o['message']}')}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await Clipboard.setData(ClipboardData(text: '${o['message']}'));
      if (mounted) _toast(tr('WhatsApp haikufunguka. Ujumbe umenakiliwa: ubandike mwenyewe.'));
    }
  }

  Future<void> _open(Map<String, dynamic> o) async {
    final status = '${o['status']}';
    final (label, color) = _label(status);
    final lines = ((o['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cardColor,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
            Row(children: [
              Expanded(
                child: Text('${(o['supplier'] as Map?)?['name'] ?? tr('Bila msambazaji')}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            ]),
            Text(
              [
                _when(o),
                if (o['created_by'] != null) tr('na :a', {'a': o['created_by']}),
                if (o['purchase'] is Map && (o['purchase'] as Map)['invoice_number'] != null) tr('ankara :a', {'a': (o['purchase'] as Map)['invoice_number']}),
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: mutedText),
            ),
            const SizedBox(height: 12),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text('${l['product']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text('${l['pack_name']} ${l['packs']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
            if (o['message'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFDCF5DE), borderRadius: BorderRadius.circular(14)),
                child: Text('${o['message']}', style: const TextStyle(fontSize: 13, height: 1.4)),
              ),
            ],
            const SizedBox(height: 14),
            if (status == 'draft') ...[
              // Carry on where it was left: add products from the lists, change amounts, save again.
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  _continueDraft(o);
                },
                icon: const Icon(Icons.edit_note),
                label: const T('Endelea kuhariri'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  _finishDraft(o);
                },
                icon: const Icon(Icons.send_rounded),
                label: const T('Iko tayari: tuma'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  _post('purchase-orders/${o['id']}', tr('Rasimu imefutwa.'), delete: true);
                },
                child: const T('Futa rasimu', style: TextStyle(color: dangerRed)),
              ),
            ],
            if (status == 'sent') ...[
              FilledButton.icon(
                onPressed: () => _whatsApp(o),
                icon: const Icon(Icons.chat_rounded),
                label: const T('Fungua WhatsApp tena'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  _post('purchase-orders/${o['id']}/cancel', tr('Agizo limeghairiwa.'));
                },
                child: const T('Ghairi agizo: halitakuja', style: TextStyle(color: dangerRed)),
              ),
            ],
            if (o['message'] != null && status != 'draft')
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: '${o['message']}'));
                  if (mounted) _toast(tr('Ujumbe umenakiliwa.'));
                },
                child: const T('Nakili ujumbe'),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickSupplier() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: cardColor,
      builder: (sheet) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: const T('Wasambazaji wote'), onTap: () => Navigator.of(sheet).pop('')),
          ListTile(title: const T('Bila msambazaji'), onTap: () => Navigator.of(sheet).pop('none')),
          for (final s in widget.suppliers) ListTile(title: Text('${s['name']}'), onTap: () => Navigator.of(sheet).pop('${s['id']}')),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    setState(() => _supplier = v);
    _load();
  }

  String get _supplierLabel {
    if (_supplier.isEmpty) return tr('Wasambazaji wote');
    if (_supplier == 'none') return tr('Bila msambazaji');
    return '${widget.suppliers.firstWhere((s) => '${s['id']}' == _supplier, orElse: () => {'name': '?'})['name']}';
  }

  // ------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: pageBackground,
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          T('Maagizo', style: TextStyle(fontWeight: FontWeight.w800)),
          T('Rasimu, yaliyotumwa, yaliyofika', style: TextStyle(fontSize: 12, color: mutedText)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (v, label) in _statuses)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(tr(label)),
                    selected: _status == v,
                    showCheckmark: false,
                    selectedColor: brandGreen,
                    labelStyle: TextStyle(color: _status == v ? Colors.white : inkColor, fontWeight: FontWeight.w700),
                    onSelected: (_) {
                      setState(() => _status = v);
                      _load();
                    },
                  ),
                ),
            ]),
          ),
          if (widget.suppliers.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: _pickSupplier, icon: const Icon(Icons.storefront_outlined, size: 18), label: Text(_supplierLabel)),
            ),
          if (_loading && _orders.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: AfyaLoader())),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: dangerRed))),
          if (!_loading && _error == null && _orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: T('Hakuna agizo hapa.', textAlign: TextAlign.center, style: TextStyle(color: mutedText)),
            ),
          for (final o in _orders) _card(o),
        ]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> o) {
    final (label, color) = _label('${o['status']}');
    final lines = ((o['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: softCard(radius: 18),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('${(o['supplier'] as Map?)?['name'] ?? tr('Bila msambazaji')}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${tr('bidhaa :n', {'n': lines.length})}: ${lines.map((l) => l['product']).take(3).join(', ')}${lines.length > 3 ? '…' : ''}\n${_when(o)}',
          maxLines: 3,
        ),
        isThreeLine: true,
        trailing: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
        onTap: () => _open(o),
      ),
    );
  }
}
