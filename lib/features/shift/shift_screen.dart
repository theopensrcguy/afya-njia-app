import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/session.dart';

/// Screens 4 and 6 of the mockups: the shift and the cash drawer.
///
/// Open a shift with the cash already in the drawer ("float"). While it is
/// open, everyone sees its sales, the payment split, the cash that SHOULD be
/// in the drawer, and anything that needs attention (cancelled sales, big
/// discounts). Close it by counting the drawer: the gap is worked out by the
/// server, and any gap needs a written reason.
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key, required this.session});

  final Session session;

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  Map<String, dynamic>? _shift; // null = no open shift
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _closing = false; // showing the "count the drawer" form

  // Owned by the screen and disposed in dispose(): safe, unlike controllers
  // created inside a function that opens a dialog.
  final _floatController = TextEditingController();
  final _countedController = TextEditingController();
  final _noteController = TextEditingController();

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _countedController.addListener(() => setState(() {})); // live gap while typing
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _floatController.dispose();
    _countedController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await _api.get('shifts/current');
      if (!mounted) return;
      setState(() => _shift = openShiftOrNull(data));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      await _api.post('shifts', {'opening_float': int.tryParse(_floatController.text) ?? 0});
      _floatController.clear();
      await _load();
      _message('Zamu imefunguliwa.');
    } on ApiException catch (e) {
      _message(e.message, isError: true); // e.g. "Kuna zamu iliyo wazi tayari."
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final counted = int.tryParse(_countedController.text);
    if (counted == null) {
      _message('Andika kiasi ulichohesabu kwenye droo.', isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await _api.post('shifts/${_shift!['shift_id']}/close', {
        'counted_cash': counted,
        'note': _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      }) as Map<String, dynamic>;
      if (!mounted) return;
      await _showClosed(result);
      _countedController.clear();
      _noteController.clear();
      setState(() => _closing = false);
      await _load();
    } on ApiException catch (e) {
      // "Kuna tofauti ya fedha. Andika sababu." when there's a gap and no note.
      _message(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showClosed(Map<String, dynamic> r) {
    final variance = asInt(r['variance']);
    final ok = variance == 0;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded, color: ok ? brandGreen : dangerRed, size: 48),
        title: const Text('Zamu imefungwa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('Ilitarajiwa', formatTsh(asInt(r['expected_cash']))),
            _row('Imehesabiwa', formatTsh(asInt(r['counted_cash']))),
            const Divider(),
            _row(ok ? 'Hakuna tofauti' : 'Tofauti', ok ? '' : formatTsh(variance), color: ok ? brandGreen : dangerRed, bold: true),
          ],
        ),
        actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Sawa'))],
      ),
    );
  }

  void _message(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: isError ? dangerRed : null));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zamu na fedha')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: const TextStyle(color: dangerRed)),
                    ),
                  if (_shift == null) ..._openForm() else ..._openShift(_shift!),
                ],
              ),
            ),
    );
  }

  List<Widget> _openForm() {
    return [
      const Text('Hakuna zamu iliyo wazi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text(
        'Fungua zamu mwanzoni mwa kazi. Mauzo ya taslimu yatahesabiwa, '
        'na mwisho wa zamu utahesabu droo kuona kama fedha zinalingana.',
        style: TextStyle(color: mutedText),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _floatController,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: 'Fedha zilizopo kwenye droo sasa (TSh)',
          helperText: 'Chenji ya kuanzia. Weka 0 kama droo ni tupu.',
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 56,
        child: FilledButton.icon(
          onPressed: _busy ? null : _open,
          icon: const Icon(Icons.lock_open),
          label: const Text('Fungua zamu', style: TextStyle(fontSize: 17)),
        ),
      ),
    ];
  }

  List<Widget> _openShift(Map<String, dynamic> s) {
    final opened = parseDate(s['opened_at']);
    final byPayment = moneyMap(s['by_payment']);
    final expected = asInt(s['expected_cash']);
    final attention = ((s['needs_attention'] as List?) ?? const []).cast<Map>();

    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: brandGreen, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Zamu ya ${s['user']} · tangu ${opened != null ? formatTime(opened) : '-'}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text(formatTsh(asInt(s['sales_total'])),
                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
            Text('Mauzo ${asInt(s['sales_count'])}', style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _panel([
        const Text('Jinsi walivyolipa', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (byPayment.isEmpty) const Text('Hakuna mauzo bado.', style: TextStyle(color: mutedText)),
        for (final e in byPayment.entries) _row(paymentLabels[e.key] ?? e.key, formatTsh(e.value)),
        const Divider(),
        // Only cash goes in the drawer: mobile money and insurance don't.
        _row('Inatarajiwa kwenye droo', formatTsh(expected), bold: true),
        const Text('Chenji ya kuanzia + mauzo ya taslimu', style: TextStyle(fontSize: 12, color: mutedText)),
      ]),
      if (attention.isNotEmpty) ...[
        const SizedBox(height: 12),
        _panel(
          [
            Text('Yanahitaji kuangaliwa · ${attention.length}', style: const TextStyle(fontWeight: FontWeight.w700, color: dangerRed)),
            const SizedBox(height: 4),
            for (final a in attention) _attentionRow(a),
          ],
          border: const Color(0xFFF3C9C4),
        ),
      ],
      const SizedBox(height: 16),
      if (!_closing)
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: inkColor),
            onPressed: () => setState(() => _closing = true),
            icon: const Icon(Icons.lock_outline),
            label: const Text('Funga zamu na hesabu fedha', style: TextStyle(fontSize: 16)),
          ),
        )
      else
        ..._closeForm(expected),
    ];
  }

  Widget _attentionRow(Map a) {
    final at = parseDate(a['at']);
    final voided = a['kind'] == 'voided';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(voided ? Icons.cancel_outlined : Icons.local_offer_outlined, size: 20, color: dangerRed),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(voided ? 'Mauzo yamefutwa · ${formatTsh(asInt(a['amount']))}' : 'Punguzo kubwa · ${formatTsh(asInt(a['amount']))}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${at != null ? formatTime(at) : ''} · ${a['by']} · ${a['receipt_number']}'
                  '${voided && a['reason'] != null ? '\nSababu: ${a['reason']}' : ''}',
                  style: const TextStyle(fontSize: 12, color: mutedText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Count the drawer. The gap updates while typing, before anything is sent.
  List<Widget> _closeForm(int expected) {
    final counted = int.tryParse(_countedController.text);
    final gap = counted == null ? null : counted - expected;

    return [
      _panel([
        const Text('Hesabu fedha kwenye droo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        TextField(
          controller: _countedController,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(labelText: 'Taslimu iliyohesabiwa (TSh)'),
        ),
        const SizedBox(height: 12),
        _row('Inatarajiwa', formatTsh(expected)),
        if (gap != null)
          _row(
            gap == 0 ? 'Inalingana' : 'Tofauti',
            gap == 0 ? '✓' : formatTsh(gap),
            color: gap == 0 ? brandGreen : dangerRed,
            bold: true,
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: gap != null && gap != 0 ? 'Sababu ya tofauti (lazima)' : 'Maelezo (si lazima)',
            hintText: 'Mf. chenji ya jana, matumizi ya duka…',
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _busy ? null : () => setState(() => _closing = false),
              child: const Text('Ghairi'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: inkColor),
              onPressed: _busy ? null : _close,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Funga zamu', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _panel(List<Widget> children, {Color border = const Color(0xFFE6E8E2)}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _row(String label, String value, {Color? color, bool bold = false}) {
    final style = TextStyle(color: color, fontWeight: bold ? FontWeight.w700 : FontWeight.normal, fontSize: bold ? 16 : 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(value, style: style)]),
    );
  }
}
