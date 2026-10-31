import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/session.dart';

/// Today's sales, newest first. The owner sees everyone's; a helper sees
/// only his own (the server decides that, not the app).
///
/// Tapping a sale shows its lines and lets you cancel ("futa") it with a
/// reason. Cancelled sales stay in the list, crossed out: nothing is ever
/// deleted, so the owner always sees what was cancelled, by whom and why.
class SalesListScreen extends StatefulWidget {
  const SalesListScreen({super.key, required this.session});

  final Session session;

  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  List<Map<String, dynamic>> _sales = [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.session.api;
  bool get _isOwner => widget.session.user!.isOwner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await _api.get('sales') as List<dynamic>;
      if (!mounted) return;
      setState(() => _sales = data.cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isVoided(Map<String, dynamic> s) => s['status'] == 'voided';

  @override
  Widget build(BuildContext context) {
    final completed = _sales.where((s) => !_isVoided(s));
    final total = completed.fold<int>(0, (sum, s) => sum + asInt(s['total']));

    return Scaffold(
      appBar: AppBar(title: Text(_isOwner ? 'Mauzo ya leo' : 'Mauzo yangu ya leo')),
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
                  // Summary line: what counts (completed sales only).
                  Text('${completed.length} mauzo · ${formatTsh(total)}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  if (_sales.length > completed.length)
                    Text('Yaliyofutwa: ${_sales.length - completed.length}', style: const TextStyle(color: dangerRed)),
                  const SizedBox(height: 12),
                  if (_sales.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Text('Hakuna mauzo leo bado.', textAlign: TextAlign.center, style: TextStyle(color: mutedText)),
                    ),
                  for (final s in _sales) _saleTile(s),
                ],
              ),
            ),
    );
  }

  Widget _saleTile(Map<String, dynamic> s) {
    final voided = _isVoided(s);
    final soldAt = parseDate(s['sold_at']);
    final items = (s['items'] as List?) ?? const [];
    final names = items.map((i) => ((i as Map)['product'] as Map?)?['name'] ?? '').toSet().join(', ');
    final seller = (s['user'] as Map?)?['name'] ?? '';
    final strike = voided ? TextDecoration.lineThrough : null;

    return Card(
      elevation: 0,
      color: voided ? const Color(0xFFFDF3F2) : Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => _showDetail(s),
        title: Text(names, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, decoration: strike)),
        subtitle: Text(
          '${soldAt != null ? formatTime(soldAt) : ''} · ${s['receipt_number']}'
          ' · ${paymentLabels[s['payment_method']] ?? s['payment_method']}'
          '${_isOwner ? ' · $seller' : ''}'
          '${voided ? '\nImefutwa: ${s['void_reason'] ?? ''}' : ''}',
          style: TextStyle(color: voided ? dangerRed : mutedText),
        ),
        isThreeLine: voided,
        trailing: Text(formatTsh(asInt(s['total'])),
            style: TextStyle(fontWeight: FontWeight.w700, decoration: strike, color: voided ? mutedText : inkColor)),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> s) {
    final voided = _isVoided(s);
    final items = ((s['items'] as List?) ?? const []).cast<Map>();
    final discount = asInt(s['discount']);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${s['receipt_number']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text('Na ${(s['user'] as Map?)?['name'] ?? ''} · ${paymentLabels[s['payment_method']] ?? s['payment_method']}',
                  style: const TextStyle(color: mutedText)),
              const Divider(height: 24),
              // One line per batch on the server; show it as the helper thinks of it.
              for (final i in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text('${(i['product'] as Map?)?['name'] ?? ''}  × ${asInt(i['quantity'])}')),
                      Text(formatTsh(asInt(i['line_total']))),
                    ],
                  ),
                ),
              const Divider(height: 24),
              if (discount > 0) _row('Punguzo', '− ${formatTsh(discount)}'),
              _row('Jumla', formatTsh(asInt(s['total'])), bold: true),
              if (voided) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(10)),
                  child: Text('Imefutwa${parseDate(s['voided_at']) != null ? ' saa ${formatTime(parseDate(s['voided_at'])!)}' : ''}.'
                      ' Sababu: ${s['void_reason'] ?? '-'}',
                      style: const TextStyle(color: dangerRed)),
                ),
              ] else ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: dangerRed, minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Futa mauzo haya'),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _void(s);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = TextStyle(fontSize: bold ? 18 : 14, fontWeight: bold ? FontWeight.w700 : FontWeight.normal);
    return Row(children: [Expanded(child: Text(label, style: style)), Text(value, style: style)]);
  }

  /// Cancel a sale. A reason is required. The server checks the rules:
  /// a helper may only cancel his own sale within a few minutes; after that
  /// it answers "Mmiliki pekee..." and we just show that message.
  Future<void> _void(Map<String, dynamic> s) async {
    final reason = await askText(
      context,
      title: 'Futa ${s['receipt_number']}?',
      message: 'Jumla ${formatTsh(asInt(s['total']))}. Dawa zitarudishwa kwenye hisa.',
      label: 'Sababu (lazima)',
      hint: 'Mf. dawa isiyo sahihi',
      confirm: 'Futa',
      danger: true,
      required: true,
    );
    if (reason == null || !mounted) return;

    try {
      await _api.post('sales/${s['id']}/void', {'reason': reason});
      _message('Mauzo yamefutwa. Dawa zimerudi kwenye hisa.');
      _load();
    } on ApiException catch (e) {
      _message(e.message, isError: true);
    }
  }

  void _message(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: isError ? dangerRed : null));
  }
}
