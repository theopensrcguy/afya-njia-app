import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../auth/change_pin_screen.dart';
import '../devices/devices_screen.dart';
import '../expiry/expiry_screen.dart';
import '../bulk/bulk_entry_screen.dart';
import '../orders/reorder_screen.dart';
import '../suppliers/suppliers_screen.dart';
import '../purchases/purchases_screen.dart';
import '../purchases/receive_screen.dart';
import '../sale/counter_screen.dart';
import '../sales/sales_list_screen.dart';
import '../shift/shift_screen.dart';
import '../staff/staff_permissions_screen.dart';
import '../staff/staff_profile.dart';
import '../stock/stock_screen.dart';
import 'widgets/recent_sales_card.dart';
import 'widgets/target_ring.dart';
import 'widgets/trend_card.dart';

/// After login (v0.2, the "Mint Laini" design).
///
/// Owner: today's sales with the goal ring, four action tiles, the week/month
/// chart and the latest sales. Helper: his own sales today, selling, the shift.
///
/// Money is HIDDEN by default (TSh ••••••): the phone lies on the counter where
/// customers can see it. The eye shows it, and the choice is remembered.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});

  final Session session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _hideKey = 'hide_amounts';
  static const _storage = FlutterSecureStorage();

  Map<String, dynamic>? _today; // owner: GET dashboard/today
  List<Map<String, dynamic>> _mySales = []; // helper: GET sales (today, his own)
  Map<String, dynamic>? _shift; // GET shifts/current (null = no open shift)
  bool _hidden = true;
  bool _loading = true;
  String? _error;
  int _tick = 0; // goes up on every refresh, so the chart reloads too

  ApiClient get _api => widget.session.api;
  /// What this person may do (the owner: everything). Buttons follow it;
  /// the server enforces it.
  bool _can(String permission) => widget.session.user!.can(permission);

  /// The shop-wide view (today's total, goal ring, chart, alerts) or one's own.
  bool get _shopView => _can(Perm.viewShopSales);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final saved = await _storage.read(key: _hideKey);
      if (mounted && saved != null) setState(() => _hidden = saved == '1');
      _load();
    });
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      // Both requests at once: the screen waits for the slower one, not for both in a row.
      // Permissions may have changed since last time (granted, revoked, expired).
      await widget.session.refreshMe();
      final results = await Future.wait([
        _shopView ? _api.get('dashboard/today') : _api.get('sales'),
        _api.get('shifts/current'),
      ]);
      if (!mounted) return;
      setState(() {
        if (_shopView) {
          _today = results[0] as Map<String, dynamic>;
        } else {
          _mySales = (results[0] as List).cast<Map<String, dynamic>>();
        }
        _shift = openShiftOrNull(results[1]);
        _tick++;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleHidden() {
    setState(() => _hidden = !_hidden);
    _storage.write(key: _hideKey, value: _hidden ? '1' : '0');
  }

  /// Open a screen, and refresh the numbers when coming back from it.
  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  String _money(int amount) => _hidden ? 'TSh ••••••' : formatTsh(amount);

  // ---------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The bottom bar floats over the list, so the list scrolls under it.
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  children: [
                    _header(),
                    const SizedBox(height: 18),
                    if (_error != null) _errorBox(),
                    if (_shift == null) _noShiftBanner(),
                    _shopView ? _ownerTodayCard() : _helperTodayCard(),
                    const SizedBox(height: 14),
                    _tiles(),
                    if (_shopView) ...[
                      const SizedBox(height: 14),
                      TrendCard(api: _api, hidden: _hidden, refreshTick: _tick),
                    ],
                    const SizedBox(height: 14),
                    _recentSales(),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _header() {
    final user = widget.session.user!;
    final shiftText = _shift == null ? 'hakuna zamu iliyo wazi' : 'zamu ya ${_shift!['user']} iko wazi';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${greeting()}, ${user.name}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              Text('${swahiliDate(DateTime.now())} · $shiftText', style: const TextStyle(fontSize: 13, color: mutedText)),
            ],
          ),
        ),
        if (_shopView) _bell(),
      ],
    );
  }

  Widget _bell() {
    final count = _alerts().length;
    return Semantics(
      button: true,
      label: 'Tahadhari $count',
      child: InkWell(
        onTap: _showAlerts,
        customBorder: const CircleBorder(),
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: cardColor,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x1A1E503C), blurRadius: 14, offset: Offset(0, 4))],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.notifications_none_rounded, color: inkColor),
              if (count > 0)
                Positioned(
                  top: 9,
                  right: 10,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: const Color(0xFFE0614A), shape: BoxShape.circle, border: Border.all(color: cardColor, width: 2)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBox() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(child: Text(_error!, style: const TextStyle(color: dangerRed))),
          TextButton(onPressed: _load, child: const Text('Jaribu tena')),
        ],
      ),
    );
  }

  /// No open shift = cash sales are not counted against a drawer. Say so.
  Widget _noShiftBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFFFFF4DC),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(ShiftScreen(session: widget.session)),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.lock_clock_outlined, color: warnAmber),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Fungua zamu ili fedha za droo zihesabiwe',
                      style: TextStyle(color: warnAmber, fontWeight: FontWeight.w700)),
                ),
                Icon(Icons.chevron_right, color: warnAmber),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _eyeButton(String what) {
    return IconButton(
      onPressed: _toggleHidden,
      tooltip: _hidden ? 'Onyesha $what' : 'Ficha $what',
      icon: Icon(_hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: mutedText),
    );
  }

  Widget _paymentRows(Map<String, int> byPayment) {
    return Column(
      children: [
        for (final method in const ['cash', 'mobile', 'insurance'])
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: paymentColors[method], shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(paymentLabels[method]!, style: const TextStyle(fontSize: 13, color: mutedText))),
                Text(_hidden ? '•••' : formatTsh(byPayment[method] ?? 0).replaceFirst('TSh ', ''),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ today cards

  Widget _ownerTodayCard() {
    final t = _today ?? const {};
    final total = asInt(t['sales_total']);
    final target = t['daily_target'] == null ? null : asInt(t['daily_target']);
    final pct = target == null || target == 0 ? 0 : (total * 100 / target).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 8, 18),
      decoration: softCard(),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: Text('Mauzo ya leo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              _eyeButton('mauzo'),
            ],
          ),
          Row(
            children: [
              TargetRing(
                progress: _hidden || target == null || target == 0 ? 0 : total / target,
                centerText: target == null ? 'Weka' : (_hidden ? '••' : '$pct%'),
                caption: target == null ? 'lengo' : 'ya lengo',
                // The daily goal is the owner's call (pharmacy settings are never delegated).
                onTap: widget.session.user!.isOwner ? () => _setTarget(target) : null,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(_money(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      ),
                      _paymentRows(moneyMap(t['by_payment'])),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The helper sees only his own sales: no shop total, no goal.
  Widget _helperTodayCard() {
    final done = _mySales.where((s) => s['status'] == 'completed').toList();
    final total = done.fold<int>(0, (sum, s) => sum + asInt(s['total']));
    final byPayment = <String, int>{};
    for (final s in done) {
      final m = '${s['payment_method']}';
      byPayment[m] = (byPayment[m] ?? 0) + asInt(s['total']);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 6, 8, 18),
      decoration: softCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Mauzo yangu ya leo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              _eyeButton('mauzo yangu'),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_money(total), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                Text('Mauzo ${done.length}', style: const TextStyle(color: mutedText)),
                _paymentRows(byPayment),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tap the ring: set, change or remove the daily goal (stored on the server).
  Future<void> _setTarget(int? current) async {
    final answer = await askText(
      context,
      title: 'Lengo la mauzo kwa siku',
      message: 'Kiasi unachotaka kuuza kila siku. Pete itaonyesha umefika wapi.',
      label: 'Kiasi (TSh)',
      hint: 'mfano 250000',
      initial: current?.toString() ?? '',
      digitsOnly: true,
      clearLabel: current != null ? 'Ondoa lengo' : null,
    );
    if (answer == null || !mounted) return; // cancelled
    try {
      await _api.patch('pharmacy/settings', {'daily_sales_target': answer.isEmpty ? null : int.parse(answer)});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ------------------------------------------------------------------ tiles

  Widget _tiles() {
    final t = _today ?? const {};
    final expiring = asInt(((t['expiring_30_days'] as Map?) ?? const {})['batches']);
    final reorder = ((t['low_stock'] as List?) ?? const []).length;

    final tiles = <Widget>[
      if (_can(Perm.sell))
        _tile(Icons.add_rounded, 'Uza sasa', () => _open(CounterScreen(session: widget.session)), primary: true),
      // Deliveries come in every week: stock in is as important as stock out.
      if (_can(Perm.receive))
        _tile(Icons.local_shipping_outlined, 'Pokea mzigo', () => _open(ReceiveScreen(session: widget.session)),
            color: const Color(0xFF7A5BC7)),
      if (!_shopView) ...[
        _tile(Icons.point_of_sale_outlined, 'Zamu', () => _open(ShiftScreen(session: widget.session)), color: brandGreen),
        if (_can(Perm.receive) || _can(Perm.confirmDeliveries))
          _tile(Icons.inventory_outlined, _can(Perm.confirmDeliveries) ? 'Mizigo ya kuthibitisha' : 'Mizigo yangu',
              () => _open(PurchasesScreen(session: widget.session)), color: brandGreen),
      ],
      if (_can(Perm.viewStock)) ...[
        _tile(Icons.hourglass_bottom_rounded, expiring > 0 ? 'Muda · $expiring' : 'Muda wa kuisha',
            () => _open(ExpiryScreen(session: widget.session)), color: const Color(0xFFD0533C)),
        _tile(Icons.inventory_2_outlined, reorder > 0 ? 'Kuagiza · $reorder' : 'Hisa',
            () => _open(StockScreen(session: widget.session, initialFilter: reorder > 0 ? 'chache' : 'zote')),
            color: const Color(0xFFC98A00)),
      ],
    ];

    // Two per row; GridView inside a ListView would need shrinkWrap, rows are simpler.
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
            child: Row(
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 12),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
              ],
            ),
          ),
      ],
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap, {bool primary = false, Color color = brandGreen}) {
    return Material(
      color: primary ? brandGreen : cardColor,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, color: primary ? Colors.white : color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: primary ? FontWeight.w800 : FontWeight.w700,
                      color: primary ? Colors.white : inkColor,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------- recent sales

  Widget _recentSales() {
    final List<Map<String, dynamic>> sales;
    final int count;
    if (_shopView) {
      sales = (((_today ?? const {})['recent_sales'] as List?) ?? const []).cast<Map<String, dynamic>>();
      count = asInt(_today?['sales_count']);
    } else {
      final done = _mySales.where((s) => s['status'] == 'completed').toList();
      sales = done.take(4).map(RecentSalesCard.fromSaleJson).toList();
      count = done.length;
    }
    return RecentSalesCard(
      sales: sales,
      totalCount: count,
      hidden: _hidden,
      onSeeAll: () => _open(SalesListScreen(session: widget.session)),
    );
  }

  // ----------------------------------------------------------------- alerts

  /// Only the things that need the owner's attention.
  List<({IconData icon, Color color, String title, String subtitle, Widget screen})> _alerts() {
    final t = _today;
    if (t == null) return [];
    final voided = asInt(t['voided_count']);
    final discount = asInt(t['discount_total']);
    final lowStock = ((t['low_stock'] as List?) ?? const []).cast<Map>();
    // 0 in stock is not "running low", it's out of stock: a different, more urgent alert.
    final outOfStock = lowStock.where((p) => asInt(p['on_hand']) <= 0).toList();
    final runningLow = lowStock.where((p) => asInt(p['on_hand']) > 0).toList();
    final expiring = (t['expiring_30_days'] as Map?) ?? const {};
    final expiringBatches = asInt(expiring['batches']);
    final sales = SalesListScreen(session: widget.session);
    final stock = StockScreen(session: widget.session, initialFilter: 'chache');

    final waiting = asInt(t['pending_purchases']);

    return [
      // First: stock that arrived but isn't counted until the owner says so.
      if (waiting > 0)
        (
          icon: Icons.local_shipping_outlined,
          color: const Color(0xFF7A5BC7),
          title: 'Mizigo $waiting ya kuthibitisha',
          subtitle: 'Hisa yake bado haijaongezwa. Ithibitishe au ikatae.',
          screen: PurchasesScreen(session: widget.session),
        ),
      if (outOfStock.isNotEmpty)
        (icon: Icons.remove_shopping_cart_outlined, color: dangerRed, title: 'Bidhaa ${outOfStock.length} zimeisha (hazipo)', subtitle: _names(outOfStock), screen: stock),
      if (expiringBatches > 0)
        (
          icon: Icons.event_busy_outlined,
          color: warnAmber,
          title: 'Batch $expiringBatches zimeisha au zinaisha ndani ya siku 30',
          subtitle: 'Thamani ${formatTsh(asInt(expiring['value_at_cost']))} (kwa bei ya kununua)',
          screen: ExpiryScreen(session: widget.session),
        ),
      if (runningLow.isNotEmpty)
        (icon: Icons.inventory_2_outlined, color: warnAmber, title: 'Bidhaa ${runningLow.length} zinakaribia kuisha', subtitle: _names(runningLow), screen: stock),
      if (voided > 0)
        (icon: Icons.cancel_outlined, color: dangerRed, title: 'Mauzo $voided yamefutwa leo', subtitle: 'Angalia sababu kwenye mauzo ya leo', screen: sales),
      if (discount > 0)
        (icon: Icons.local_offer_outlined, color: warnAmber, title: 'Punguzo leo: ${formatTsh(discount)}', subtitle: 'Jumla ya punguzo zote zilizotolewa', screen: sales),
    ];
  }

  String _names(List<Map> items) =>
      items.take(3).map((p) => '${p['name']}').join(', ') + (items.length > 3 ? '…' : '');

  void _showAlerts() {
    final alerts = _alerts();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cardColor,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text('Tahadhari', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            if (alerts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Hakuna tahadhari. Kila kitu kiko sawa.', style: TextStyle(color: mutedText)),
              ),
            for (final a in alerts)
              ListTile(
                leading: Icon(a.icon, color: a.color),
                title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(a.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _open(a.screen);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ bottom bar

  Widget _bottomBar() {
    Widget item(IconData icon, String label, VoidCallback? onTap, {bool active = false}) {
      final color = active ? brandGreen : mutedText;
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Container(
        height: 64,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x291E503C), blurRadius: 30, offset: Offset(0, 10))],
        ),
        child: Row(
          children: [
            item(Icons.home_rounded, 'Nyumbani', null, active: true),
            item(Icons.receipt_long_outlined, _shopView ? 'Mauzo' : 'Mauzo yangu', () => _open(SalesListScreen(session: widget.session))),
            // Stock is used every day, next to sales; reports live under Zaidi.
            if (_can(Perm.viewStock)) item(Icons.inventory_2_outlined, 'Hisa', () => _open(StockScreen(session: widget.session))),
            item(Icons.more_horiz_rounded, 'Zaidi', _showMore),
          ],
        ),
      ),
    );
  }

  /// Everything that is not used every hour lives here.
  void _showMore() {
    void go(BuildContext sheet, Widget screen) {
      Navigator.of(sheet).pop();
      _open(screen);
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cardColor,
      showDragHandle: true,
      // By default a sheet stops at ~56% of the screen; the menu grew past
      // that ("overflowed"). Let it take what it needs, and scroll on small phones.
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
         child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.point_of_sale_outlined),
              title: const Text('Zamu na hesabu ya fedha'),
              onTap: () => go(sheet, ShiftScreen(session: widget.session)),
            ),
            if (_can(Perm.receive) || _can(Perm.confirmDeliveries))
              ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text(_can(Perm.confirmDeliveries) ? 'Mizigo ya kuthibitisha' : 'Mizigo yangu'),
                onTap: () => go(sheet, PurchasesScreen(session: widget.session)),
              ),
            // Made for a laptop (web): many lines with a keyboard. On a phone it
            // still works, but Pokea mzigo is the phone's way.
            if (_can(Perm.receive))
              ListTile(
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Ingiza kwa wingi'),
                subtitle: Text(MediaQuery.of(sheet).size.width >= 900 ? 'Hisa ya mwanzo, mizigo mikubwa' : 'Bora kwenye kompyuta'),
                onTap: () => go(sheet, BulkEntryScreen(session: widget.session)),
              ),
            if (_can(Perm.prepareOrders))
              ListTile(
                leading: const Icon(Icons.shopping_cart_checkout_rounded),
                title: const Text('Agiza mzigo'),
                subtitle: const Text('Zitakazoisha kabla mzigo ujao'),
                onTap: () => go(sheet, ReorderScreen(session: widget.session)),
              ),
            if (_can(Perm.receive) || _can(Perm.prepareOrders))
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Wasambazaji'),
                onTap: () => go(sheet, SuppliersScreen(session: widget.session)),
              ),
            if (_can(Perm.viewStock))
              ListTile(
                leading: const Icon(Icons.hourglass_bottom_rounded),
                title: const Text('Muda wa kuisha'),
                onTap: () => go(sheet, ExpiryScreen(session: widget.session)),
              ),
            if (_can(Perm.viewShopSales))
              ListTile(
                leading: const Icon(Icons.bar_chart_rounded),
                title: const Text('Ripoti'),
                subtitle: const Text('Inakuja hivi karibuni'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ripoti zinakuja hivi karibuni.')));
                },
              ),
            if (_can(Perm.manageDevices))
              ListTile(
                leading: const Icon(Icons.phonelink_lock),
                title: const Text('Simu zinazoruhusiwa'),
                onTap: () => go(sheet, DevicesScreen(session: widget.session)),
              ),
            // Never delegable: only the owner decides who may do what.
            if (widget.session.user!.isOwner)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Wafanyakazi na ruhusa'),
                subtitle: const Text('Toa au ondoa ruhusa, kwa muda au kudumu'),
                onTap: () => go(sheet, StaffPermissionsScreen(session: widget.session)),
              ),
            if (!widget.session.user!.isOwner)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Taarifa zangu'),
                subtitle: const Text('Duka limehifadhi nini kukuhusu, na nani ameangalia'),
                onTap: () => go(sheet, MyProfileScreen(session: widget.session)),
              ),
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: const Text('Badilisha PIN yangu'),
              onTap: () => go(sheet, ChangePinScreen(session: widget.session)),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: dangerRed),
              title: const Text('Toka', style: TextStyle(color: dangerRed)),
              onTap: () {
                Navigator.of(sheet).pop();
                widget.session.logout();
              },
            ),
          ],
         ),
        ),
      ),
    );
  }
}
