import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/loader.dart';
import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/permissions.dart';
import '../../core/session.dart';
import '../auth/change_pin_screen.dart';
import '../devices/devices_screen.dart';
import '../billing/pay_dialog.dart';
import '../credit/madeni_screen.dart';
import '../customers/customers_screen.dart';
import '../expenses/matumizi_screen.dart';
import '../transfers/my_shops_screen.dart';
import '../transfers/transfers_screen.dart';
import '../expiry/expiry_screen.dart';
import '../bulk/bulk_entry_screen.dart';
import '../orders/reorder_screen.dart';
import '../suppliers/suppliers_screen.dart';
import '../support/support_screen.dart';
import '../purchases/purchases_screen.dart';
import '../purchases/receive_screen.dart';
import '../sale/counter_screen.dart';
import '../sales/sales_list_screen.dart';
import '../shift/shift_screen.dart';
import '../staff/staff_permissions_screen.dart';
import '../staff/staff_profile.dart';
import '../stock/stock_screen.dart';
import '../stock/stock_count_screen.dart';
import 'widgets/recent_sales_card.dart';
import 'widgets/target_ring.dart';
import 'widgets/trend_card.dart';
import '../../core/i18n.dart';

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
    // Never arrive with a keyboard left over from signing in.
    SystemChannels.textInput.invokeMethod('TextInput.hide');
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

  String _money(int amount) => _hidden ? tr('TSh ••••••') : formatTsh(amount);

  // ---------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The bottom bar floats over the list, so the list scrolls under it.
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: AfyaLoader())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  children: [
                    _header(),
                    const SizedBox(height: 18),
                    if (_error != null) _errorBox(),
                    ?_billingBanner(),
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

  /// Paying: the owner is warned near the end; everyone sees it when the shop is read-only.
  Widget? _billingBanner() {
    final user = widget.session.user!;
    final s = user.subscription;
    if (s == null || s['warn'] != true || !(user.isOwner || user.readOnly)) return null;
    final bad = user.readOnly;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bad ? const Color(0xFFFDE8E6) : const Color(0xFFFFF4DC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(bad ? Icons.lock_outline : Icons.info_outline, color: bad ? dangerRed : warnAmber),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s['message'] ?? ''}', style: TextStyle(color: bad ? dangerRed : const Color(0xFF7A5300), fontWeight: FontWeight.w600)),
            if (user.isOwner)
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                onPressed: user.canPayOnline
                    ? () async {
                        final paid = await payForShop(context, api: widget.session.api, placeId: user.id, shopName: tr('duka hili'));
                        if (paid) await widget.session.refreshMe();
                        if (mounted) setState(() {});
                      }
                    : () => _open(MyShopsScreen(session: widget.session)),
                child: T(user.canPayOnline ? 'Lipia sasa' : 'Angalia malipo'),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _header() {
    final user = widget.session.user!;
    final shiftText = _shift == null ? tr('hakuna zamu iliyo wazi') : tr('zamu ya :a iko wazi', {'a': _shift!['user']});
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
      label: tr('Tahadhari :count', {'count': count}),
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
          TextButton(onPressed: _load, child: const T('Jaribu tena')),
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
                  child: T('Fungua zamu ili fedha za droo zihesabiwe',
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
      tooltip: _hidden ? tr('Onyesha :what', {'what': what}) : tr('Ficha :what', {'what': what}),
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
              const Expanded(child: T('Mauzo ya leo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              _eyeButton(tr('mauzo')),
            ],
          ),
          Row(
            children: [
              TargetRing(
                progress: _hidden || target == null || target == 0 ? 0 : total / target,
                centerText: target == null ? tr('Weka') : (_hidden ? '••' : '$pct%'),
                caption: target == null ? tr('lengo') : tr('ya lengo'),
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
              const Expanded(child: T('Mauzo yangu ya leo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              _eyeButton(tr('mauzo yangu')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_money(total), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                Text(tr('Mauzo :done', {'done': done.length}), style: const TextStyle(color: mutedText)),
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
      title: tr('Lengo la mauzo kwa siku'),
      message: tr('Kiasi unachotaka kuuza kila siku. Pete itaonyesha umefika wapi.'),
      label: tr('Kiasi (TSh)'),
      hint: tr('mfano 250000'),
      initial: current?.toString() ?? '',
      digitsOnly: true,
      clearLabel: current != null ? tr('Ondoa lengo') : null,
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

  String _debtsLabel(Map t) {
    final d = (t['debts'] as Map?) ?? const {};
    final total = asInt(d['total']);
    final pending = asInt(d['pending']);
    if (pending > 0 && _can(Perm.manageCredit)) return tr('Maombi ya deni · :n', {'n': pending});
    return total > 0 ? tr('Madeni · :a', {'a': formatTsh(total)}) : tr('Madeni');
  }

  Widget _tiles() {
    final t = _today ?? const {};
    final expiring = asInt(((t['expiring_30_days'] as Map?) ?? const {})['batches']);
    final reorder = ((t['low_stock'] as List?) ?? const []).length;

    final tiles = <Widget>[
      if (_can(Perm.sell))
        _tile(Icons.add_rounded, tr('Uza sasa'), () => _open(CounterScreen(session: widget.session)), primary: true),
      // Deliveries come in every week: stock in is as important as stock out.
      if (_can(Perm.receive))
        _tile(Icons.local_shipping_outlined, tr('Pokea mzigo'), () => _open(ReceiveScreen(session: widget.session)),
            color: const Color(0xFF7A5BC7)),
      if (!_shopView) ...[
        _tile(Icons.point_of_sale_outlined, tr('Zamu'), () => _open(ShiftScreen(session: widget.session)), color: brandGreen),
        if (_can(Perm.receive) || _can(Perm.confirmDeliveries))
          _tile(Icons.inventory_outlined, _can(Perm.confirmDeliveries) ? tr('Mizigo ya kuthibitisha') : tr('Mizigo yangu'),
              () => _open(PurchasesScreen(session: widget.session)), color: brandGreen),
      ],
      // Madeni: what customers owe now (and who waits for approval).
      if (!_shopView && (_can(Perm.sellOnCredit) || _can(Perm.manageCredit)))
        _tile(Icons.account_balance_wallet_outlined, _debtsLabel(t), () => _open(MadeniScreen(session: widget.session)),
            color: const Color(0xFF2F6FB0)),
      if (_can(Perm.viewStock)) ...[
        _tile(Icons.hourglass_bottom_rounded, expiring > 0 ? tr('Muda · :expiring', {'expiring': expiring}) : tr('Muda wa kuisha'),
            () => _open(ExpiryScreen(session: widget.session)), color: const Color(0xFFD0533C)),
        _tile(Icons.inventory_2_outlined, reorder > 0 ? tr('Kuagiza · :reorder', {'reorder': reorder}) : tr('Hisa'),
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
          title: tr('Mizigo :waiting ya kuthibitisha', {'waiting': waiting}),
          subtitle: tr('Hisa yake bado haijaongezwa. Ithibitishe au ikatae.'),
          screen: PurchasesScreen(session: widget.session),
        ),
      if (outOfStock.isNotEmpty)
        (icon: Icons.remove_shopping_cart_outlined, color: dangerRed, title: tr('Bidhaa :out_of_stock zimeisha (hazipo)', {'out_of_stock': outOfStock.length}), subtitle: _names(outOfStock), screen: stock),
      if (expiringBatches > 0)
        (
          icon: Icons.event_busy_outlined,
          color: warnAmber,
          title: tr('Batch :expiring_batches zimeisha au zinaisha ndani ya siku 30', {'expiring_batches': expiringBatches}),
          subtitle: tr('Thamani :a (kwa bei ya kununua)', {'a': formatTsh(asInt(expiring['value_at_cost']))}),
          screen: ExpiryScreen(session: widget.session),
        ),
      if (runningLow.isNotEmpty)
        (icon: Icons.inventory_2_outlined, color: warnAmber, title: tr('Bidhaa :running_low zinakaribia kuisha', {'running_low': runningLow.length}), subtitle: _names(runningLow), screen: stock),
      if (voided > 0)
        (icon: Icons.cancel_outlined, color: dangerRed, title: tr('Mauzo :voided yamefutwa leo', {'voided': voided}), subtitle: tr('Angalia sababu kwenye mauzo ya leo'), screen: sales),
      if (discount > 0)
        (icon: Icons.local_offer_outlined, color: warnAmber, title: tr('Punguzo leo: :a', {'a': formatTsh(discount)}), subtitle: tr('Jumla ya punguzo zote zilizotolewa'), screen: sales),
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
              child: T('Tahadhari', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            if (alerts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: T('Hakuna tahadhari. Kila kitu kiko sawa.', style: TextStyle(color: mutedText)),
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
            item(Icons.home_rounded, tr('Nyumbani'), null, active: true),
            item(Icons.receipt_long_outlined, _shopView ? tr('Mauzo') : tr('Mauzo yangu'), () => _open(SalesListScreen(session: widget.session))),
            // Stock is used every day, next to sales; reports live under Zaidi.
            if (_can(Perm.viewStock)) item(Icons.inventory_2_outlined, tr('Hisa'), () => _open(StockScreen(session: widget.session))),
            item(Icons.more_horiz_rounded, tr('Zaidi'), _showMore),
          ],
        ),
      ),
    );
  }

  /// Everything that is not used every hour: one page, in groups (like the
  /// web's sidebar), with a search box. A long flat list was hard to scan.
  void _showMore() {
    final u = widget.session.user!;
    final wide = MediaQuery.of(context).size.width >= 900;
    final items = <_MoreItem>[
      // Kila siku
      _MoreItem('day', Icons.point_of_sale_outlined, tr('Zamu na fedha'), tr('Fungua zamu, hesabu fedha ya droo'),
          () => _open(ShiftScreen(session: widget.session))),
      if (_can(Perm.sellOnCredit) || _can(Perm.manageCredit))
        _MoreItem('day', Icons.account_balance_wallet_outlined, tr('Madeni'), tr('Wanaodaiwa, malipo, kuidhinisha'),
            () => _open(MadeniScreen(session: widget.session))),
      if (_can(Perm.recordExpenses))
        _MoreItem('day', Icons.receipt_long_outlined, tr('Matumizi'), tr('Kodi, umeme, mishahara…'), () => _open(MatumiziScreen(session: widget.session))),
      if (_can(Perm.viewCustomers))
        _MoreItem('day', Icons.people_alt_outlined, tr('Wateja'), tr('Historia yao, na vikumbusho (si lazima)'),
            () => _open(CustomersScreen(session: widget.session))),
      // Hisa
      if (_can(Perm.receive) || _can(Perm.confirmDeliveries))
        _MoreItem('stock', Icons.local_shipping_outlined, _can(Perm.confirmDeliveries) ? tr('Mizigo') : tr('Mizigo yangu'),
            _can(Perm.confirmDeliveries) ? tr('Ya kuthibitisha, na iliyopita') : null, () => _open(PurchasesScreen(session: widget.session))),
      if (_can(Perm.prepareOrders))
        _MoreItem('stock', Icons.shopping_cart_checkout_rounded, tr('Agiza'), tr('Zitakazoisha kabla mzigo ujao'), () => _open(ReorderScreen(session: widget.session))),
      if (_can(Perm.countStock) || _can(Perm.adjustStock))
        _MoreItem('stock', Icons.fact_check_outlined, tr('Hesabu ya hisa'), tr('Linganisha rafu na mfumo'),
            () => _open(StockCountScreen(session: widget.session))),
      if (_can(Perm.viewStock))
        _MoreItem('stock', Icons.hourglass_bottom_rounded, tr('Muda wa kuisha'), null, () => _open(ExpiryScreen(session: widget.session))),
      if (_can(Perm.receive) || _can(Perm.prepareOrders))
        _MoreItem('stock', Icons.storefront_outlined, tr('Wasambazaji'), null, () => _open(SuppliersScreen(session: widget.session))),
      if (_can(Perm.viewStock) && (_can(Perm.transferStock) || _can(Perm.approveTransfers)))
        _MoreItem('stock', Icons.swap_horiz_rounded, tr('Uhamisho'), tr('Hamisha hisa kwenda duka jingine, au pokea'),
            () => _open(TransfersScreen(session: widget.session))),
      // Made for a laptop: many lines with a keyboard.
      if (_can(Perm.receive))
        _MoreItem('stock', Icons.table_chart_outlined, tr('Ingiza kwa wingi'), wide ? tr('Hisa ya mwanzo, mizigo mikubwa') : tr('Bora kwenye kompyuta'),
            () => _open(BulkEntryScreen(session: widget.session))),
      if (_can(Perm.viewShopSales))
        _MoreItem('stock', Icons.bar_chart_rounded, tr('Ripoti'), tr('Inakuja hivi karibuni'),
            () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: T('Ripoti zinakuja hivi karibuni.')))),
      // Duka na watu
      if (u.isOwner || u.otherShops > 0)
        _MoreItem('shop', Icons.storefront_rounded, tr('Maduka yangu'), tr('Badili duka bila kutoka'), () => _open(MyShopsScreen(session: widget.session))),
      if (u.isOwner)
        _MoreItem('shop', Icons.admin_panel_settings_outlined, tr('Wafanyakazi'), tr('Toa au ondoa ruhusa, kwa muda au kudumu'),
            () => _open(StaffPermissionsScreen(session: widget.session))),
      if (_can(Perm.manageDevices))
        _MoreItem('shop', Icons.phonelink_lock, tr('Vifaa'), tr('Simu na kompyuta zinazoruhusiwa'), () => _open(DevicesScreen(session: widget.session))),
      if (!u.isOwner)
        _MoreItem('shop', Icons.badge_outlined, tr('Taarifa zangu'), tr('Duka limehifadhi nini kukuhusu, na nani ameangalia'),
            () => _open(MyProfileScreen(session: widget.session))),
      // Mimi
      _MoreItem('me', Icons.pin_outlined, tr('Badilisha PIN'), null, () => _open(ChangePinScreen(session: widget.session))),
      _MoreItem('me', Icons.support_agent_rounded, tr('Msaada'), tr('Uliza Saola, ona majibu'), () => _open(SupportScreen(session: widget.session))),
    ];
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MoreScreen(session: widget.session, items: items),
    ));
  }
}

/// One entry of the Zaidi page.
class _MoreItem {
  const _MoreItem(this.section, this.icon, this.label, this.subtitle, this.onTap);

  final String section; // day | stock | shop | me
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
}

/// Zaidi: the rest of the app in four groups, as tiles, with a search box.
/// Tapping a tile closes this page and opens the screen from home, so Back
/// returns to home (not to this menu).
class _MoreScreen extends StatefulWidget {
  const _MoreScreen({required this.session, required this.items});

  final Session session;
  final List<_MoreItem> items;

  @override
  State<_MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<_MoreScreen> {
  String _q = '';

  static const _sections = [
    ('day', 'Kila siku', Icons.today_rounded, Color(0xFF1B7F64)),
    ('stock', 'Hisa na mizigo', Icons.inventory_2_outlined, Color(0xFF2563EB)),
    ('shop', 'Duka na watu', Icons.groups_outlined, Color(0xFF7C3AED)),
    ('me', 'Mimi', Icons.person_outline_rounded, Color(0xFF5B6F69)),
  ];

  void _go(_MoreItem item) {
    Navigator.of(context).pop();
    item.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.session.user!;
    final q = _q.trim().toLowerCase();
    final shown = widget.items.where((i) => q.isEmpty || i.label.toLowerCase().contains(q) || (i.subtitle ?? '').toLowerCase().contains(q)).toList();
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1000 ? 5 : (width >= 700 ? 4 : 3);
    final initials = u.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(backgroundColor: pageBackground, title: const T('Zaidi', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              // Who is signed in.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: primarySoft,
                    child: Text(initials, style: const TextStyle(color: primaryStrong, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(u.isOwner ? tr('Mmiliki') : tr('Mfanyakazi'), style: const TextStyle(color: mutedText, fontSize: 13)),
                    ]),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.session.logout();
                    },
                    icon: const Icon(Icons.logout_rounded, color: dangerRed, size: 20),
                    label: const T('Toka', style: TextStyle(color: dangerRed, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (v) => setState(() => _q = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: tr('Tafuta: mf. madeni, PIN, wateja…'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: cardColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              for (final (key, title, icon, colour) in _sections)
                if (shown.any((i) => i.section == key)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
                    child: Row(children: [
                      Icon(icon, size: 18, color: colour),
                      const SizedBox(width: 8),
                      Text(tr(title).toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: mutedText)),
                    ]),
                  ),
                  GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.95,
                    children: [for (final item in shown.where((i) => i.section == key)) _tile(item, colour)],
                  ),
                ],
              if (shown.isEmpty)
                Padding(padding: const EdgeInsets.all(32), child: Center(child: T('Hakuna kinacholingana.', style: const TextStyle(color: mutedText)))),
              // Language: a plain row, always at the end.
              if (q.isEmpty) ...[
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    const Icon(Icons.translate_rounded, color: mutedText),
                    const SizedBox(width: 12),
                    const Expanded(child: T('Lugha', style: TextStyle(fontWeight: FontWeight.w600))),
                    LanguageSwitch(onChanged: (code) {
                      Navigator.of(context).pop();
                      widget.session.setLanguage(code);
                    }),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(_MoreItem item, Color colour) {
    return Tooltip(
      message: item.subtitle ?? item.label,
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _go(item),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: colour.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
                child: Icon(item.icon, color: colour),
              ),
              const SizedBox(height: 10),
              Text(item.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.2)),
            ]),
          ),
        ),
      ),
    );
  }
}

