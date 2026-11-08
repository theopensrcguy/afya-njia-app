import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/ids.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../suppliers/supplier_form.dart';
import 'new_product.dart';
import 'receive_line.dart';
import 'receive_line_screen.dart';
import '../../core/i18n.dart';

/// "Pokea mzigo": record a supplier delivery.
///
/// The owner's delivery counts at once. The helper's is sent to the owner and
/// counts only after the owner confirms it, because whoever records
/// deliveries could otherwise add stock that never arrived.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key, required this.session});

  final Session session;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  List<Map<String, dynamic>> _suppliers = [];
  int? _supplierId;
  final _invoice = TextEditingController();
  final _invoiceTotal = TextEditingController();
  final List<ReceiveLine> _lines = [];
  // Bytes, not a path: works on the phone and in a browser alike.
  Uint8List? _photoBytes;
  String _photoName = 'ankara.jpg';
  bool _saving = false;
  String? _error;

  /// One id for this delivery, made on the phone. If the network drops while
  /// saving, pressing save again sends the same id and the server won't record
  /// the delivery twice (same idea as sales).
  final String _deliveryId = randomId();

  ApiClient get _api => widget.session.api;
  /// Does my delivery count at once, or wait for someone to confirm it?
  /// A new product I may not create on my own (create_products + edit_prices)
  /// makes it wait too: it is checked together with the stock (the server decides the same way).
  bool get _countsNow {
    final me = widget.session.user!;
    final mayCreate = me.can(Perm.createProducts) && me.can(Perm.editPrices);
    return me.can(Perm.receiveUnconfirmed) && (mayCreate || _drafts.isEmpty);
  }

  /// New products on this delivery, once each (two batches share one).
  List<NewProductDraft> get _drafts {
    final seen = <NewProductDraft>{};
    return [for (final l in _lines) if (l.newProduct != null && seen.add(l.newProduct!)) l.newProduct!];
  }
  int get _total => _lines.fold(0, (t, l) => t + l.total);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuppliers());
  }

  @override
  void dispose() {
    _invoice.dispose();
    _invoiceTotal.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final data = (await _api.get('suppliers') as List).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _suppliers = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _addSupplier() async {
    // Name is enough; phone, location, TIN... can be added now or later.
    final s = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => SupplierFormScreen(api: _api)));
    if (s == null || !mounted) return;
    setState(() {
      _suppliers = [..._suppliers, s]..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      _supplierId = asInt(s['id']);
    });
  }

  String? get _supplierName {
    for (final s in _suppliers) {
      if (asInt(s['id']) == _supplierId) return '${s['name']}';
    }
    return null;
  }

  Future<void> _editLine([int? index]) async {
    final line = await Navigator.of(context).push<ReceiveLine>(MaterialPageRoute(
      builder: (_) => ReceiveLineScreen(
        api: _api,
        supplierId: _supplierId,
        supplierName: _supplierName,
        initial: index == null ? null : _lines[index],
        canPrice: widget.session.user!.can(Perm.editPrices),
        drafts: _drafts,
      ),
    ));
    if (line == null || !mounted) return;
    setState(() {
      if (index == null) {
        _lines.add(line);
      } else {
        _lines[index] = line;
      }
    });
  }

  /// Camera, or a photo already taken (the invoice may have been photographed
  /// earlier; also the only way on the iOS Simulator, which has no camera).
  Future<void> _takePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      backgroundColor: cardColor,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const T('Piga picha sasa'),
            onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const T('Chagua kutoka picha'),
            onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;

    try {
      // Smaller than full size: still readable, and quick on mobile data.
      final file = await ImagePicker().pickImage(source: source, imageQuality: 60, maxWidth: 1600);
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() {
            _photoBytes = bytes;
            _photoName = file.name;
          });
        }
      }
    } on MissingPluginException {
      // The camera is native code: added packages need a full rebuild, not hot restart.
      _toast(tr('Kamera haijawekwa kwenye app hii bado. Simamisha app (q) na uendeshe "flutter run" upya.'), error: true);
    } on PlatformException catch (e) {
      _toast(
        e.code.contains('access_denied')
            ? tr('Ruhusa ya kamera/picha imekataliwa. Fungua Settings › Afya Njia na uiruhusu.')
            : tr('Kamera haipatikani (:code). Jaribu "Chagua kutoka picha".', {'code': e.code}),
        error: true,
      );
    } catch (e) {
      // Never fail silently: say what happened.
      _toast(tr('Imeshindwa kupata picha: :e', {'e': e}), error: true);
    }
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? dangerRed : null));
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) {
      setState(() => _error = tr('Ongeza angalau bidhaa moja.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await _api.post('purchases', {
        'client_uuid': _deliveryId,
        'supplier_id': _supplierId,
        'invoice_number': _invoice.text.trim().isEmpty ? null : _invoice.text.trim(),
        'invoice_total': int.tryParse(_invoiceTotal.text.trim()),
        'lines': [for (final l in _lines) l.toJson()],
      }) as Map<String, dynamic>;

      // The delivery is saved. The photo is extra: if it fails, say so but
      // don't lose the delivery.
      var photoFailed = false;
      if (_photoBytes != null) {
        try {
          await _api.upload('purchases/${res['id']}/photo', 'photo', _photoBytes!, _photoName);
        } on ApiException {
          photoFailed = true;
        }
      }
      if (!mounted) return;

      final pending = res['status'] == 'pending';
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          icon: Icon(pending ? Icons.schedule_send : Icons.check_circle, color: brandGreen, size: 40),
          title: Text(pending ? tr('Imetumwa kwa uthibitisho') : tr('Mzigo umehifadhiwa')),
          content: Text([
            pending
                ? (_drafts.isEmpty
                    ? tr('Hisa itaongezeka baada ya kuthibitishwa.')
                    : tr('Hisa itaongezeka baada ya kuthibitishwa. Bidhaa mpya :drafts zitaanza kuuzwa zikithibitishwa.', {'drafts': _drafts.length}))
                : tr('Hisa imeongezeka: bidhaa :lines, :a.', {'lines': _lines.length, 'a': formatTsh(_total)}),
            if (photoFailed) tr('Picha ya ankara haikutumwa (mtandao).'),
          ].join('\n')),
          actions: [FilledButton(onPressed: () => Navigator.of(dialog).pop(), child: const T('Sawa'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final unsure = e.code == 'offline' || e.code == 'timeout';
      setState(() => _error = unsure
          // Same id next time, so pressing again is safe.
          ? tr(':message Bonyeza tena: mzigo hautahifadhiwa mara mbili.', {'message': e.message})
          : e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const T('Toka bila kuhifadhi?'),
        content: Text(tr('Bidhaa :lines zilizoongezwa zitapotea.', {'lines': _lines.length})),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const T('Hapana')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const T('Toka')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  // ----------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _lines.isEmpty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: const T('Pokea mzigo'), backgroundColor: pageBackground),
        body: Column(children: [
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              children: [
                _supplierCard(),
                const SizedBox(height: 16),
                Row(children: [
                  Text(tr('Bidhaa :lines', {'lines': _lines.length}), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (_lines.isNotEmpty) const T('Gusa kubadilisha', style: TextStyle(fontSize: 12, color: mutedText)),
                ]),
                const SizedBox(height: 8),
                for (var i = 0; i < _lines.length; i++) _lineCard(i),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _editLine(),
                  icon: const Icon(Icons.add),
                  label: const T('Ongeza bidhaa'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
                const SizedBox(height: 14),
                _totalsCard(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_countsNow ? tr('Hisa inaongezeka mara moja.') : tr('Hisa itaongezeka baada ya mzigo kuthibitishwa.'),
                    style: const TextStyle(fontSize: 12, color: mutedText)),
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: _saving || _lines.isEmpty ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  child: Text(_saving ? tr('Inatuma…') : (_countsNow ? tr('Hifadhi mzigo') : tr('Tuma uthibitishwe'))),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _supplierCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: softCard(radius: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const T('Msambazaji', style: TextStyle(color: mutedText)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final s in _suppliers)
            ChoiceChip(
              label: Text('${s['name']}'),
              selected: _supplierId == asInt(s['id']),
              showCheckmark: false,
              selectedColor: brandGreen,
              labelStyle: TextStyle(color: _supplierId == asInt(s['id']) ? Colors.white : inkColor, fontWeight: FontWeight.w700),
              // Tap again to unselect (a delivery without a known supplier is allowed).
              onSelected: (on) => setState(() => _supplierId = on ? asInt(s['id']) : null),
            ),
          ActionChip(label: const T('+ Mpya'), onPressed: _addSupplier),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _invoice,
          decoration: InputDecoration(labelText: tr('Namba ya ankara (si lazima)')),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: T('Picha ya ankara (si lazima)', style: TextStyle(color: mutedText))),
          if (_photoBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_photoBytes!, width: 44, height: 44, fit: BoxFit.cover),
            ),
            IconButton(tooltip: tr('Ondoa picha'), onPressed: () => setState(() => _photoBytes = null), icon: const Icon(Icons.close)),
          ] else
            FilledButton.tonalIcon(onPressed: _takePhoto, icon: const Icon(Icons.photo_camera_outlined), label: const T('Piga picha')),
        ]),
      ]),
    );
  }

  Widget _lineCard(int i) {
    final l = _lines[i];
    Widget tag(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: mintSoft, borderRadius: BorderRadius.circular(8)),
          child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ObjectKey(l),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: const Color(0xFFFDE7E4), borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.delete_outline, color: dangerRed),
        ),
        onDismissed: (_) => setState(() => _lines.removeAt(i)),
        child: Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _saving ? null : () => _editLine(i),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(l.product.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                  Text(formatTsh(l.total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 4),
                Text(l.describe(), style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (l.newProduct != null) tag(l.newProduct!.hasPrices ? tr('Bidhaa mpya') : tr('Bidhaa mpya · bila bei')),
                  if (l.barcode != null) tag(tr('Barcode imefunzwa')),
                  tag(tr('Batch :batch', {'batch': l.batch})),
                  tag(tr('Inaisha :expiry_text', {'expiry_text': l.expiryText})),
                  tag(tr(':a kila moja', {'a': formatTsh(l.packCost)})),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// The delivery's total against the invoice's total: a mismatch means a
  /// line was typed wrong (or the invoice is wrong). Catch it before saving.
  Widget _totalsCard() {
    final invoiceTotal = int.tryParse(_invoiceTotal.text.trim());
    final match = invoiceTotal == null ? null : invoiceTotal == _total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: softCard(radius: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: T('Jumla ya mzigo', style: TextStyle(color: mutedText))),
          Text(formatTsh(_total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _invoiceTotal,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: tr('Jumla kwenye ankara (si lazima)')),
        ),
        if (match != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              match ? tr('✓ Inalingana na ankara') : tr('Tofauti ya :a: angalia bidhaa na bei.', {'a': formatTsh((invoiceTotal! - _total).abs())}),
              style: TextStyle(fontWeight: FontWeight.w800, color: match ? brandGreen : dangerRed),
            ),
          ),
      ]),
    );
  }
}
