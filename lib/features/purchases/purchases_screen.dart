import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/units.dart';

const _statusLabels = {
  'pending': ('Inasubiri', warnAmber, Color(0xFFFBEFD6)),
  'received': ('Imepokelewa', brandGreen, Color(0xFFDDF3EA)),
  'rejected': ('Imekataliwa', dangerRed, Color(0xFFFDE7E4)),
};

/// Deliveries. Owner: the ones waiting for confirmation (stock not counted
/// yet). Helper: his own, so he sees whether the owner accepted them.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key, required this.session});

  final Session session;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  bool get _isOwner => widget.session.user!.isOwner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final data = await widget.session.api.get('purchases', query: {if (_isOwner) 'status': 'pending'}) as List;
      if (mounted) setState(() => _items = data.cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> p) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PurchaseReviewScreen(session: widget.session, purchase: p)),
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isOwner ? 'Mizigo inayosubiri' : 'Mizigo yangu'), backgroundColor: pageBackground),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
                  if (_items.isEmpty && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Text(_isOwner ? 'Hakuna mzigo unaosubiri.' : 'Bado hujarekodi mzigo.',
                          textAlign: TextAlign.center, style: const TextStyle(color: mutedText)),
                    ),
                  for (final p in _items) _card(p),
                ],
              ),
            ),
    );
  }

  Widget _card(Map<String, dynamic> p) {
    final (label, fg, bg) = _statusLabels[p['status']] ?? ('${p['status']}', mutedText, mintSoft);
    final at = parseDate(p['received_at']);
    final lines = (p['lines'] as List?) ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _open(p),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${(p['supplier'] as Map?)?['name'] ?? 'Msambazaji hajulikani'} · bidhaa ${lines.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${p['received_by'] ?? ''} · ${at == null ? '' : '${swahiliDate(at.toLocal())} ${formatTime(at)}'}',
                      style: const TextStyle(fontSize: 12, color: mutedText)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatTsh(asInt(p['total_cost'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                  child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One delivery in full. For the owner, a pending one ends with
/// Kataa (reason required) / Thibitisha (stock goes up now).
class PurchaseReviewScreen extends StatefulWidget {
  const PurchaseReviewScreen({super.key, required this.session, required this.purchase});

  final Session session;
  final Map<String, dynamic> purchase;

  @override
  State<PurchaseReviewScreen> createState() => _PurchaseReviewScreenState();
}

class _PurchaseReviewScreenState extends State<PurchaseReviewScreen> {
  late Map<String, dynamic> _p = widget.purchase;
  Future<dynamic>? _photo;
  bool _busy = false;

  ApiClient get _api => widget.session.api;
  bool get _isOwner => widget.session.user!.isOwner;

  @override
  void initState() {
    super.initState();
    // The photo is private on the server: fetched with the token, owner only.
    if (_isOwner && _p['has_photo'] == true) _photo = _api.getBytes('purchases/${_p['id']}/photo');
  }

  Future<void> _decide(bool accept) async {
    String? reason;
    if (!accept) {
      reason = await askText(context,
          title: 'Kataa mzigo', label: 'Sababu', hint: 'mfano: bei hailingani na ankara', required: true, danger: true, confirm: 'Kataa');
      if (reason == null) return;
    }
    setState(() => _busy = true);
    try {
      final res = await _api.post('purchases/${_p['id']}/${accept ? 'confirm' : 'reject'}', {'reason': ?reason})
          as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _p = res);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accept ? 'Imethibitishwa. Hisa imeongezeka.' : 'Mzigo umekataliwa.'),
      ));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: dangerRed));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _p['status'] == 'pending';
    final (label, fg, bg) = _statusLabels[_p['status']] ?? ('${_p['status']}', mutedText, mintSoft);
    final at = parseDate(_p['received_at']);
    final lines = ((_p['lines'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final invoiceTotal = _p['invoice_total'] == null ? null : asInt(_p['invoice_total']);
    final total = asInt(_p['total_cost']);

    return Scaffold(
      appBar: AppBar(title: const Text('Mzigo'), backgroundColor: pageBackground),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: softCard(radius: 22),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                    child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 8),
                  _kv('Imerekodiwa na', '${_p['received_by'] ?? ''} · ${at == null ? '' : '${swahiliDate(at.toLocal())} ${formatTime(at)}'}'),
                  _kv('Msambazaji', '${(_p['supplier'] as Map?)?['name'] ?? '—'}'),
                  _kv('Ankara', '${_p['invoice_number'] ?? '—'}'),
                  if (_p['confirmed_by'] != null) _kv(_p['status'] == 'rejected' ? 'Imekataliwa na' : 'Imethibitishwa na', '${_p['confirmed_by']}'),
                  if (_p['rejected_reason'] != null) _kv('Sababu', '${_p['rejected_reason']}'),
                ]),
              ),
              if (_photo != null) _photoThumb(),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: softCard(radius: 22),
            child: Column(children: [
              for (var i = 0; i < lines.length; i++) _line(lines[i], last: i == lines.length - 1),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: softCard(radius: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('Jumla ya mzigo', style: TextStyle(color: mutedText))),
                Text(formatTsh(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ]),
              if (invoiceTotal != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    invoiceTotal == total
                        ? '✓ Inalingana na ankara (${formatTsh(invoiceTotal)})'
                        : 'Ankara inasema ${formatTsh(invoiceTotal)}: tofauti ${formatTsh((invoiceTotal - total).abs())}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: invoiceTotal == total ? brandGreen : dangerRed),
                  ),
                ),
            ]),
          ),
          if (_isOwner && pending) ...[
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _decide(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    foregroundColor: dangerRed,
                    side: const BorderSide(color: dangerRed, width: 2),
                  ),
                  child: const Text('Kataa'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _busy ? null : () => _decide(true),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  child: Text(_busy ? 'Inatuma…' : 'Thibitisha mzigo'),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 12, color: mutedText)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _photoThumb() {
    return FutureBuilder<dynamic>(
      future: _photo,
      builder: (context, snap) {
        final bytes = snap.data;
        return GestureDetector(
          onTap: bytes == null
              ? null
              : () => showDialog<void>(
                    context: context,
                    builder: (d) => Dialog(
                      insetPadding: const EdgeInsets.all(8),
                      child: InteractiveViewer(child: Image.memory(bytes)), // pinch to zoom the invoice
                    ),
                  ),
          child: Container(
            width: 96,
            height: 124,
            decoration: BoxDecoration(color: mintSoft, borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: bytes != null
                ? Image.memory(bytes, fit: BoxFit.cover)
                : Center(
                    child: snap.hasError
                        ? const Icon(Icons.broken_image_outlined, color: mutedText)
                        : const CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
        );
      },
    );
  }

  Widget _line(Map<String, dynamic> l, {required bool last}) {
    final packName = l['pack_name'] as String?;
    final size = asInt(l['pack_size']);
    final packs = asInt(l['packs']);
    final expiry = parseDate(l['expiry_date']);
    final pack = size == 1 || packName == null ? '$packs' : '$packs ${unitLabel(packName, packs)} × $size = ${asInt(l['quantity'])}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFE3EDE8)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${l['product']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          Text(formatTsh(asInt(l['line_total'])), style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        Text(
          '$pack · ${l['batch_number']} · inaisha ${expiry == null ? '' : '${expiry.month.toString().padLeft(2, '0')}/${expiry.year}'}'
          ' · ${formatTsh(asInt(l['pack_cost']))} kila moja',
          style: const TextStyle(fontSize: 12, color: mutedText),
        ),
      ]),
    );
  }
}
