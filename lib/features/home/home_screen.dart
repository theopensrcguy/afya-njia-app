import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../devices/devices_screen.dart';
import '../expiry/expiry_screen.dart';
import '../sale/counter_screen.dart';
import '../sales/sales_list_screen.dart';
import '../shift/shift_screen.dart';
import '../stock/stock_alerts_screen.dart';

/// After login. The owner sees screen 1 of the mockups: today's numbers and
/// alerts at the top, the shop's actions below. The helper sees only what a
/// helper needs: selling, his own sales, and the shift.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});

  final Session session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _today; // owner: GET dashboard/today
  Map<String, dynamic>? _shift; // everyone: GET shifts/current (null = no open shift)
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
      // Both requests at once: the screen waits for the slower one, not for both in a row.
      final results = await Future.wait([
        if (_isOwner) _api.get('dashboard/today') else Future.value(null),
        _api.get('shifts/current'),
      ]);
      if (!mounted) return;
      setState(() {
        _today = results[0] as Map<String, dynamic>?;
        _shift = openShiftOrNull(results[1]);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Open a screen, and refresh the numbers when coming back from it.
  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.session.user!;
    return Scaffold(
      appBar: AppBar(
        title: Text('Habari, ${user.name}'),
        actions: [
          TextButton.icon(onPressed: widget.session.logout, icon: const Icon(Icons.logout), label: const Text('Toka')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              // Pull down to refresh: the helper's latest sales appear.
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) _errorBox(),
                  if (_isOwner && _today != null) ...[
                    _todayHeader(_today!),
                    const SizedBox(height: 12),
                    ..._ownerAlerts(_today!),
                  ],
                  _shiftCard(),
                  const SizedBox(height: 16),
                  ..._actions(),
                ],
              ),
            ),
    );
  }

  Widget _errorBox() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: Text(_error!, style: const TextStyle(color: dangerRed))),
          TextButton(onPressed: _load, child: const Text('Jaribu tena')),
        ],
      ),
    );
  }

  /// The green block: today's sales total, count, payment split, last sale.
  Widget _todayHeader(Map<String, dynamic> t) {
    final byPayment = moneyMap(t['by_payment']);
    final lastSale = parseDate(t['last_sale_at']);
    // The whole card opens today's sales: it's the first thing the owner
    // looks at, so it should also be the first thing he can tap.
    return Material(
      color: brandGreen,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(SalesListScreen(session: widget.session)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Expanded(child: Text('Mauzo leo', style: TextStyle(color: Colors.white70))),
                  Text('Ona mauzo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
              const SizedBox(height: 4),
              Text(formatTsh(asInt(t['sales_total'])),
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Mauzo ${asInt(t['sales_count'])}'
                '${lastSale != null ? ' · ya mwisho ${timeAgo(lastSale)}' : ''}',
                style: const TextStyle(color: Colors.white70),
              ),
              if (byPayment.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in byPayment.entries)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(20)),
                        child: Text('${paymentLabels[e.key] ?? e.key}: ${formatTsh(e.value)}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Only the things that need the owner's attention. Nothing shown = all fine.
  List<Widget> _ownerAlerts(Map<String, dynamic> t) {
    final voided = asInt(t['voided_count']);
    final discount = asInt(t['discount_total']);
    final lowStock = ((t['low_stock'] as List?) ?? const []).cast<Map>();
    // 0 in stock is not "running low", it's out of stock: a different, more urgent alert.
    final outOfStock = lowStock.where((p) => asInt(p['on_hand']) <= 0).toList();
    final runningLow = lowStock.where((p) => asInt(p['on_hand']) > 0).toList();
    final expiring = (t['expiring_30_days'] as Map?) ?? const {};
    final expiringBatches = asInt(expiring['batches']);

    return [
      if (voided > 0)
        _alert(
          icon: Icons.cancel_outlined,
          color: dangerRed,
          title: 'Mauzo $voided yamefutwa leo',
          subtitle: 'Angalia sababu kwenye mauzo ya leo',
          onTap: () => _open(SalesListScreen(session: widget.session)),
        ),
      if (discount > 0)
        _alert(
          icon: Icons.local_offer_outlined,
          color: warnAmber,
          title: 'Punguzo leo: ${formatTsh(discount)}',
          subtitle: 'Jumla ya punguzo zote zilizotolewa',
          onTap: () => _open(SalesListScreen(session: widget.session)),
        ),
      if (expiringBatches > 0)
        _alert(
          icon: Icons.event_busy_outlined,
          color: warnAmber,
          title: 'Batch $expiringBatches zimeisha au zinaisha ndani ya siku 30',
          subtitle: 'Thamani ${formatTsh(asInt(expiring['value_at_cost']))} (kwa bei ya kununua)',
          onTap: () => _open(ExpiryScreen(session: widget.session)),
        ),
      if (outOfStock.isNotEmpty)
        _alert(
          icon: Icons.remove_shopping_cart_outlined,
          color: dangerRed,
          title: 'Bidhaa ${outOfStock.length} zimeisha (hazipo)',
          subtitle: _names(outOfStock),
          onTap: () => _open(StockAlertsScreen(session: widget.session)),
        ),
      if (runningLow.isNotEmpty)
        _alert(
          icon: Icons.inventory_2_outlined,
          color: warnAmber,
          title: 'Bidhaa ${runningLow.length} zinakaribia kuisha',
          subtitle: _names(runningLow),
          onTap: () => _open(StockAlertsScreen(session: widget.session)),
        ),
    ];
  }

  Widget _alert({required IconData icon, required Color color, required String title, required String subtitle, VoidCallback? onTap}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withAlpha(90))),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  String _names(List<Map> items) =>
      items.take(3).map((p) => '${p['name']}').join(', ') + (items.length > 3 ? '…' : '');

  /// Is the drawer being counted? Open shift: who and since when. None: a nudge.
  Widget _shiftCard() {
    final s = _shift;
    final opened = s == null ? null : parseDate(s['opened_at']);
    return Card(
      elevation: 0,
      color: s == null ? const Color(0xFFFFF6E5) : const Color(0xFFE7F1EC),
      margin: const EdgeInsets.only(top: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(s == null ? Icons.lock_clock_outlined : Icons.point_of_sale, color: s == null ? warnAmber : brandGreen),
        title: Text(
          s == null ? 'Hakuna zamu iliyo wazi' : 'Zamu ya ${s['user']} iko wazi',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(s == null
            ? 'Fungua zamu ili fedha za droo zihesabiwe'
            : 'Tangu ${opened != null ? formatTime(opened) : '-'} · Mauzo ${asInt(s['sales_count'])} · ${formatTsh(asInt(s['sales_total']))}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(ShiftScreen(session: widget.session)),
      ),
    );
  }

  List<Widget> _actions() {
    Widget big(IconData icon, String label, VoidCallback onTap, {bool primary = false}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          height: primary ? 64 : 56,
          child: primary
              ? FilledButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label, style: const TextStyle(fontSize: 18)))
              : OutlinedButton.icon(
                  onPressed: onTap,
                  icon: Icon(icon),
                  label: Text(label, style: const TextStyle(fontSize: 16)),
                  style: OutlinedButton.styleFrom(backgroundColor: Colors.white, alignment: Alignment.centerLeft),
                ),
        ),
      );
    }

    return [
      big(Icons.point_of_sale, 'Mauzo mapya', () => _open(CounterScreen(session: widget.session)), primary: true),
      big(Icons.receipt_long_outlined, _isOwner ? 'Mauzo ya leo' : 'Mauzo yangu ya leo',
          () => _open(SalesListScreen(session: widget.session))),
      big(Icons.lock_clock_outlined, 'Zamu na hesabu ya fedha', () => _open(ShiftScreen(session: widget.session))),
      if (_isOwner) ...[
        big(Icons.event_busy_outlined, 'Muda wa kuisha', () => _open(ExpiryScreen(session: widget.session))),
        big(Icons.phonelink_lock, 'Simu zinazoruhusiwa', () => _open(DevicesScreen(session: widget.session))),
      ],
    ];
  }
}
