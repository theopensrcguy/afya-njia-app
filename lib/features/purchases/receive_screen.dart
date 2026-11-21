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
import '../../core/smooth.dart';
import '../../core/units.dart';
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
  const ReceiveScreen({super.key, required this.session, this.supplierId});

  final Session session;

  /// Opened from a supplier's page: that supplier is already chosen.
  final int? supplierId;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  List<Map<String, dynamic>> _suppliers = [];
  late int? _supplierId = widget.supplierId;
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
        'invoice_total': moneyValue(_invoiceTotal.text),
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
  // v0.46 (canvas 13): three numbered steps (who from, the invoice, the
  // products) and a dark bar at the bottom with the total, whether it
  // matches the invoice, and the one button.

  static const _tints = [
    (Color(0xFFE7F6EF), Color(0xFF0E5A44)),
    (Color(0xFFEAF0FD), Color(0xFF2F5FC4)),
    (Color(0xFFFDF1E3), Color(0xFF7A4A12)),
    (Color(0xFFF0ECF7), Color(0xFF5B4790)),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _lines.isEmpty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: pageBackground,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Row(children: [
                Semantics(
                  button: true,
                  label: tr('Rudi'),
                  excludeSemantics: true,
                  child: Pressable(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.chevron_left_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const T('Pokea mzigo', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.3)),
                    Text(_countsNow ? tr('Hisa inaongezeka mara moja.') : tr('Hisa itaongezeka baada ya mzigo kuthibitishwa.'),
                        style: const TextStyle(fontSize: 12, color: mutedText)),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: staggered([
                  _step('1', tr('KUTOKA KWA NANI'), _supplierRow()),
                  const SizedBox(height: 12),
                  _step('2', tr('ANKARA'), _invoiceBox()),
                  const SizedBox(height: 16),
                  _linesBox(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: const TextStyle(color: dangerRed, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
            ),
            _bottomBar(),
          ]),
        ),
      ),
    );
  }

  Widget _step(String n, String title, Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('$n · $title', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .6, color: mutedText)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  /// Suppliers as round-cornered avatars; tap again to clear (allowed).
  Widget _supplierRow() {
    Widget avatar(String label, Widget face, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Semantics(
            button: true,
            selected: on,
            label: label,
            excludeSemantics: true,
            child: Pressable(
              onTap: onTap,
              child: SizedBox(
                width: 68,
                child: Column(children: [
                  AnimatedContainer(
                    duration: Motion.of(context, Motion.fast),
                    width: 54,
                    height: 54,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: on ? brandGreen : Colors.transparent, width: 2.4),
                    ),
                    child: face,
                  ),
                  const SizedBox(height: 5),
                  Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, height: 1.15, fontWeight: on ? FontWeight.w800 : FontWeight.w600)),
                ]),
              ),
            ),
          ),
        );
    return SizedBox(
      height: 92,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (var i = 0; i < _suppliers.length; i++)
          Builder(builder: (_) {
            final s = _suppliers[i];
            final id = asInt(s['id']);
            final (bg, fg) = _tints[i % _tints.length];
            final words = '${s['name']}'.trim().split(RegExp(r'\s+'));
            final initials = words.take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
            return avatar(
              '${s['name']}',
              Container(
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
                child: Center(child: Text(initials, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: fg))),
              ),
              _supplierId == id,
              () {
                HapticFeedback.selectionClick();
                setState(() => _supplierId = _supplierId == id ? null : id);
              },
            );
          }),
        avatar(
          tr('Mpya'),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF9FB3AB), width: 1.4),
            ),
            child: const Icon(Icons.add_rounded, color: mutedText),
          ),
          false,
          _addSupplier,
        ),
      ]),
    );
  }

  Widget _invoiceBox() {
    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF5F8F7),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: TextField(controller: _invoice, textCapitalization: TextCapitalization.characters, decoration: dec(tr('Namba ya ankara')))),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _invoiceTotal,
            keyboardType: TextInputType.number,
            inputFormatters: const [MoneyInput()],
            onChanged: (_) => setState(() {}),
            decoration: dec(tr('Jumla ya ankara')),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFB9CBC4), width: 1.2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _takePhoto,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _photoBytes != null
                    ? Image.memory(_photoBytes!, width: 54, height: 54, fit: BoxFit.cover)
                    : Container(width: 54, height: 54, color: const Color(0xFFEEF3F1), child: const Icon(Icons.photo_camera_outlined, color: mutedText)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_photoBytes != null ? tr('Picha ya ankara imewekwa') : tr('Piga picha ya ankara'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(_photoBytes != null ? tr('Gusa kubadilisha') : tr('Mwenye duka ataiona akithibitisha (si lazima)'),
                      style: const TextStyle(fontSize: 12, color: mutedText)),
                ]),
              ),
              if (_photoBytes != null)
                IconButton(tooltip: tr('Ondoa picha'), onPressed: () => setState(() => _photoBytes = null), icon: const Icon(Icons.close)),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _linesBox() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Row(children: [
          Text(tr('3 · BIDHAA (:n)', {'n': _lines.length}),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .6, color: mutedText)),
          const Spacer(),
          if (_lines.isNotEmpty) const T('gusa kubadilisha · telezesha kufuta', style: TextStyle(fontSize: 11.5, color: mutedText)),
        ]),
      ),
      for (var i = 0; i < _lines.length; i++) Appear(index: i, child: _lineCard(i)),
      Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: brandGreen, width: 1.4),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _saving ? null : () => _editLine(),
          child: const SizedBox(
            height: 56,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_rounded, color: brandGreen),
              SizedBox(width: 8),
              T('Ongeza bidhaa', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: brandGreen)),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _lineCard(int i) {
    final l = _lines[i];
    final now = DateTime.now();
    final monthsLeft = (l.expiryYear - now.year) * 12 + l.expiryMonth - now.month;
    final near = monthsLeft < 6;
    Widget tag(String text, {Color bg = const Color(0xFFF2F6F4), Color fg = const Color(0xFF44564F)}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
          child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ObjectKey(l),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(color: const Color(0xFFFDE7E4), borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.delete_outline, color: dangerRed),
        ),
        onDismissed: (_) => setState(() => _lines.removeAt(i)),
        child: Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _saving ? null : () => _editLine(i),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: near ? const Color(0xFFFDF1E3) : const Color(0xFFE7F6EF), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.inventory_2_outlined, size: 20, color: near ? const Color(0xFF7A4A12) : brandGreen),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.product.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(l.describe(), style: const TextStyle(fontSize: 12.5, color: Color(0xFF44564F))),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      if (l.newProduct != null)
                        tag(l.newProduct!.hasPrices ? tr('Bidhaa mpya') : tr('Bidhaa mpya · bila bei'), bg: const Color(0xFFEAF0FD), fg: const Color(0xFF2F5FC4)),
                      tag(tr('Batch :batch', {'batch': l.batch})),
                      tag('EXP ${l.expiryText}',
                          bg: near ? const Color(0xFFFDF1E3) : const Color(0xFFE7F6EF), fg: near ? const Color(0xFF7A4A12) : const Color(0xFF0E5A44)),
                      if (l.barcode != null) tag(tr('Barcode imefunzwa')),
                    ]),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(formatTsh(l.total), style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
                  Text('${formatTsh(l.packCost)} / ${unitLabel(l.packName)}', style: const TextStyle(fontSize: 11.5, color: mutedText)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// The total against the invoice's total (a mismatch means a line was
  /// typed wrong, or the invoice is), and the one button.
  Widget _bottomBar() {
    final invoiceTotal = moneyValue(_invoiceTotal.text);
    final match = invoiceTotal == null || _lines.isEmpty ? null : invoiceTotal == _total;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF14211D),
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [BoxShadow(color: Color(0x55142A23), blurRadius: 30, offset: Offset(0, 12))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Bidhaa :n · jumla ya mistari', {'n': _lines.length}), style: const TextStyle(fontSize: 12, color: Color(0xFFB7C7C1))),
                CountUp(value: _total, format: formatTsh, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
              ]),
            ),
            if (match != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: match ? const Color(0x293DDC97) : const Color(0x33F9B4A6), borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(match ? Icons.check_rounded : Icons.error_outline_rounded, size: 15, color: match ? const Color(0xFF8FE6BE) : const Color(0xFFF9B4A6)),
                  const SizedBox(width: 5),
                  Text(
                    match ? tr('Inalingana na ankara') : tr('Tofauti :a', {'a': formatTsh((invoiceTotal! - _total).abs())}),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: match ? const Color(0xFF8FE6BE) : const Color(0xFFF9B4A6)),
                  ),
                ]),
              ),
          ]),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _saving || _lines.isEmpty ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3DDC97),
              foregroundColor: const Color(0xFF0E3B31),
              disabledBackgroundColor: const Color(0xFF2B3A35),
              disabledForegroundColor: const Color(0xFF7D8F89),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: Text(_saving ? tr('Inatuma…') : (_countsNow ? tr('Hifadhi mzigo') : tr('Tuma uthibitishwe')),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}
