import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/session.dart';

/// What to reorder. Two different problems, kept apart:
///   Zimeisha (hazipo)    0 in stock: customers are being turned away TODAY.
///   Zinakaribia kuisha   at or below the reorder level: order before it hits 0.
///
/// Owner only (uses the dashboard data, which the server limits to the owner).
class StockAlertsScreen extends StatefulWidget {
  const StockAlertsScreen({super.key, required this.session});

  final Session session;

  @override
  State<StockAlertsScreen> createState() => _StockAlertsScreenState();
}

class _StockAlertsScreenState extends State<StockAlertsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await _api.get('dashboard/today') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _items = ((data['low_stock'] as List?) ?? const []).cast<Map<String, dynamic>>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final out = _items.where((p) => asInt(p['on_hand']) <= 0).toList();
    final low = _items.where((p) => asInt(p['on_hand']) > 0).toList()
      // The closest to running out first.
      ..sort((a, b) => asInt(a['on_hand']).compareTo(asInt(b['on_hand'])));

    return Scaffold(
      appBar: AppBar(title: const Text('Hisa za kuagiza')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) Text(_error!, style: const TextStyle(color: dangerRed)),
                  if (_items.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Text('Hisa zote ziko juu ya kiwango cha kuagiza.',
                          textAlign: TextAlign.center, style: TextStyle(color: mutedText)),
                    ),
                  if (out.isNotEmpty) ...[
                    _heading('Zimeisha (hazipo) · ${out.length}', dangerRed,
                        'Wateja wanakosa dawa hizi leo. Agiza sasa.'),
                    for (final p in out) _tile(p, dangerRed),
                    const SizedBox(height: 20),
                  ],
                  if (low.isNotEmpty) ...[
                    _heading('Zinakaribia kuisha · ${low.length}', warnAmber,
                        'Zimefika au ziko chini ya kiwango cha kuagiza.'),
                    for (final p in low) _tile(p, warnAmber),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _heading(String title, Color color, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color)),
          Text(subtitle, style: const TextStyle(color: mutedText, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> p, Color color) {
    final onHand = asInt(p['on_hand']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text('Kiwango cha kuagiza: ${asInt(p['reorder_level'])}',
                    style: const TextStyle(fontSize: 12, color: mutedText)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(onHand <= 0 ? '0' : '$onHand', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
              Text(onHand <= 0 ? 'hazipo' : 'zimebaki', style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}
