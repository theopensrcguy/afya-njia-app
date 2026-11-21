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
import '../../core/smooth.dart';
import '../insights/expenses_insight_screen.dart';
import '../insights/finance_screen.dart';
import '../insights/forecast_screen.dart';
import '../insights/report_screen.dart';
import '../insurance/claims_screen.dart';
import '../insights/insight_parts.dart' show kDeep, kInk, kMint;
import 'widgets/owner_home.dart';
import 'widgets/recent_sales_card.dart';
import 'widgets/saola_home.dart';
import 'widgets/stock_insight_card.dart';
import '../../core/i18n.dart';

/// After login. Owner (v0.45, canvas "Nyumbani mpya"): a compact header, one
/// period switch, the dark sales card with the goal gauge, round quick
/// actions, the day's tip, KPIs with how they moved, the week, busy hours,
/// top sellers and the stock in one line (widgets/owner_home.dart).
/// Helper: his own sales today, selling, the shift.
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
  bool get _shopView => _can(Perm.viewShopSales) && !_saola;

  /// Signed in to Saola's own workspace (v0.46.1): not a shop.
  bool get _saola => widget.session.user!.isSaolaWorkspace;

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
      // Saola's workspace is not a shop: no sales or shift to load (SaolaHome loads its own).
      if (_saola) {
        if (mounted) setState(() => _tick++);
        return;
      }
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
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                  children: [
                    _header(),
                    const SizedBox(height: 14),
                    if (_error != null) _errorBox(),
                    ?_billingBanner(),
                    if (_saola)
                      SaolaHome(api: _api, refreshTick: _tick, onSwitchShop: () => _open(MyShopsScreen(session: widget.session)))
                    else ...[
                    if (_shift == null) _noShiftBanner(),
                    if (_shopView)
                      _ownerHome()
                    else ...[
                      _helperTodayCard(),
                      const SizedBox(height: 14),
                      _tiles(),
                      // Hali ya hisa: the stock at a glance, for whoever may see stock.
                      if (_can(Perm.viewStock)) ...[
                        const SizedBox(height: 18),
                        StockInsightCard(
                          session: widget.session,
                          hidden: _hidden,
                          refreshTick: _tick,
                          onOpenStock: (f) => _open(StockScreen(session: widget.session, initialFilter: f)),
                        ),
                      ],
                    ],
                    // The owner's home ends with top sellers and stock (canvas);
                    // every sale is one tap away under Mauzo.
                    if (!_shopView) ...[const SizedBox(height: 14), _recentSales()],
                    ],
                  ],
                ),
              ),
      ),
      bottomNavigationBar: _saola ? null : _bottomBar(),
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

  String get _initials => widget.session.user!.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

  /// As on the canvas: the avatar (tap: your account), a small greeting, the
  /// name at 17, search and the bell. The shop pill sits beside the period
  /// switch for the owner, alone under the header for everyone else.
  Widget _header() {
    final user = widget.session.user!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Semantics(
          button: true,
          label: tr('Akaunti yangu'),
          excludeSemantics: true,
          child: Pressable(
            onTap: _account,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: Color(0xFFCDEFE0), shape: BoxShape.circle),
              child: Center(child: Text(_initials.isEmpty ? '·' : _initials, style: const TextStyle(color: Color(0xFF0E5A44), fontWeight: FontWeight.w800, fontSize: 15))),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _account,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(greeting(), style: const TextStyle(fontSize: 13, color: mutedText)),
              Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kInk)),
            ]),
          ),
        ),
        if (_can(Perm.viewStock) && !_saola) ...[
          _round(Icons.search_rounded, tr('Tafuta bidhaa'), () => _open(StockScreen(session: widget.session))),
          const SizedBox(width: 8),
        ],
        if (_shopView) _bell(),
      ]),
      if (!_shopView && _shopPill() != null) ...[const SizedBox(height: 12), Align(alignment: Alignment.centerLeft, child: _shopPill())],
    ]);
  }

  /// The shop's name; tap to switch when there is another shop.
  Widget? _shopPill() {
    final user = widget.session.user!;
    final shop = user.shopName;
    if (shop == null || shop.isEmpty) return null;
    final canSwitch = user.isOwner || user.otherShops > 0;
    return Semantics(
      button: canSwitch,
      label: shop,
      excludeSemantics: true,
      child: Pressable(
        onTap: canSwitch ? () => _open(MyShopsScreen(session: widget.session)) : () {},
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.storefront_outlined, size: 16, color: mutedText),
            const SizedBox(width: 6),
            Flexible(child: Text(shop, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kInk))),
            if (canSwitch) ...[const SizedBox(width: 2), const Icon(Icons.expand_more_rounded, size: 16, color: mutedText)],
          ]),
        ),
      ),
    );
  }

  /// Tapping the avatar: who is signed in, where, and the personal things
  /// (shops, PIN, my details, language, help, sign out) in one sheet.
  void _account() {
    tick();
    final u = widget.session.user!;
    final s = widget.session;
    void go(Widget screen) {
      Navigator.of(context).pop();
      _open(screen);
    }

    Widget item(IconData icon, String label, String? sub, VoidCallback onTap, {Color color = kInk}) => ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color == kInk ? pageBackground : const Color(0xFFFBE9E5), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: color),
          ),
          title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          subtitle: sub == null ? null : Text(sub, style: const TextStyle(fontSize: 12, color: mutedText)),
          trailing: color == kInk ? const Icon(Icons.chevron_right_rounded, color: mutedText) : null,
          onTap: onTap,
        );

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * .85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(color: Color(0xFFCDEFE0), shape: BoxShape.circle),
                  child: Center(child: Text(_initials, style: const TextStyle(color: Color(0xFF0E5A44), fontWeight: FontWeight.w800, fontSize: 20))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk)),
                    const SizedBox(height: 2),
                    Text(
                      [u.isOwner ? tr('Mmiliki') : tr('Mfanyakazi'), if ((u.shopName ?? '').isNotEmpty) u.shopName!].join(' · '),
                      style: const TextStyle(fontSize: 13, color: mutedText),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              if (u.isOwner || u.otherShops > 0)
                item(Icons.storefront_rounded, tr('Maduka yangu'), u.otherShops > 0 ? tr('Badili duka bila kutoka') : null, () => go(MyShopsScreen(session: s))),
              item(Icons.pin_outlined, tr('Badilisha PIN'), null, () => go(ChangePinScreen(session: s))),
              if (!u.isOwner)
                item(Icons.badge_outlined, tr('Taarifa zangu'), tr('Duka limehifadhi nini kukuhusu, na nani ameangalia'), () => go(MyProfileScreen(session: s))),
              if (_can(Perm.manageDevices))
                item(Icons.phonelink_lock, tr('Vifaa'), tr('Simu na kompyuta zinazoruhusiwa'), () => go(DevicesScreen(session: s))),
              item(Icons.support_agent_rounded, tr('Msaada'), tr('Uliza Saola, ona majibu'), () => go(SupportScreen(session: s))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: pageBackground, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.translate_rounded, size: 20, color: kInk),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(child: T('Lugha', style: TextStyle(fontWeight: FontWeight.w600, color: kInk))),
                  LanguageSwitch(onChanged: (code) {
                    Navigator.of(sheet).pop();
                    s.setLanguage(code);
                  }),
                ]),
              ),
              const Divider(height: 20),
              item(Icons.logout_rounded, tr('Toka'), tr('Utaingia tena kwa PIN yako'), () {
                Navigator.of(sheet).pop();
                s.logout();
              }, color: dangerRed),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _round(IconData icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(color: cardColor, shape: BoxShape.circle),
            child: Icon(icon, color: inkColor, size: 21),
          ),
        ),
      );

  /// The owner's body (widgets/owner_home.dart); this screen keeps the
  /// navigation, so every tap opens from here and comes back refreshed.
  Widget _ownerHome() {
    final t = _today ?? const {};
    final target = t['daily_target'] == null ? null : asInt(t['daily_target']);
    final s = widget.session;
    return OwnerHome(
      session: s,
      hidden: _hidden,
      onToggleHidden: _toggleHidden,
      refreshTick: _tick,
      showStock: _can(Perm.viewStock),
      lead: _shopPill(),
      actions: [
        if (_can(Perm.sell)) (icon: Icons.add_rounded, label: tr('Uza'), onTap: () => _open(CounterScreen(session: s)), primary: true),
        if (_can(Perm.receive)) (icon: Icons.local_shipping_outlined, label: tr('Pokea'), onTap: () => _open(ReceiveScreen(session: s)), primary: false),
        if (_can(Perm.prepareOrders)) (icon: Icons.shopping_cart_checkout_rounded, label: tr('Agiza'), onTap: () => _open(ReorderScreen(session: s)), primary: false),
        if (_can(Perm.viewStock))
          (icon: Icons.qr_code_scanner_rounded, label: tr('Skani'), onTap: () => _open(StockScreen(session: s, startWithScan: true)), primary: false),
      ],
      onOpenStock: (f) => _open(StockScreen(session: s, initialFilter: f)),
      onTip: (tip) => _open(switch ('${tip['kind']}') {
        'reorder' when _can(Perm.prepareOrders) => ReorderScreen(session: s),
        'reorder' => StockScreen(session: s, initialFilter: 'chache'),
        'expired' => ExpiryScreen(session: s),
        _ => StockScreen(session: s),
      }),
      // The daily goal is the owner's call (pharmacy settings are never delegated).
      onSetTarget: s.user!.isOwner ? () => _setTarget(target) : null,
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
          width: 42,
          height: 42,
          decoration: const BoxDecoration(color: cardColor, shape: BoxShape.circle),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.notifications_none_rounded, color: inkColor),
              if (count > 0)
                Positioned(
                  top: 8,
                  right: 9,
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

  /// No open shift = cash sales are not counted against a drawer. One slim line.
  Widget _noShiftBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFFFFF4DC),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(ShiftScreen(session: widget.session)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(children: [
              const Icon(Icons.lock_clock_outlined, color: warnAmber, size: 19),
              const SizedBox(width: 10),
              const Expanded(child: T('Zamu haijafunguliwa', style: TextStyle(color: Color(0xFF7A5300), fontWeight: FontWeight.w700, fontSize: 13.5))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: warnAmber, borderRadius: BorderRadius.circular(99)),
                child: const T('Fungua', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ]),
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
      hint: tr('mfano 250,000'),
      initial: current?.toString() ?? '',
      money: true,
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
    // Uza first and full width (v0.46.1): selling is what the helper is here for.
    return Column(
      children: [
        if (_can(Perm.sell)) ...[
          UzaButton(label: tr('Uza sasa'), height: 84, onTap: () => _open(CounterScreen(session: widget.session))),
          const SizedBox(height: 14),
        ],
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

  /// A dark floating pill; the current tab is a mint capsule with its name.
  Widget _bottomBar() {
    Widget item(IconData icon, String label, VoidCallback? onTap, {bool active = false}) {
      return Expanded(
        flex: active ? 8 : 4,
        child: Semantics(
          button: true,
          selected: active,
          label: label,
          excludeSemantics: true,
          child: Pressable(
            onTap: onTap ?? () {},
            child: Center(
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.base),
                curve: Motion.curve,
                height: 44,
                padding: EdgeInsets.symmetric(horizontal: active ? 10 : 2),
                decoration: BoxDecoration(color: active ? kMint : Colors.transparent, borderRadius: BorderRadius.circular(99)),
                child: active
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, color: kDeep, size: 20),
                        const SizedBox(width: 6),
                        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: kDeep))),
                      ])
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(icon, color: const Color(0xCCFFFFFF), size: 21),
                        const SizedBox(height: 2),
                        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xB3FFFFFF))),
                      ]),
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Container(
        height: 64,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: kInk,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [BoxShadow(color: Color(0x33142A23), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: Row(
          children: [
            item(Icons.home_rounded, tr('Nyumbani'), null, active: true),
            item(Icons.receipt_long_outlined, _shopView ? tr('Mauzo') : tr('Mauzo yangu'), () => _open(SalesListScreen(session: widget.session))),
            // Stock is used every day, next to sales.
            if (_can(Perm.viewStock)) item(Icons.inventory_2_outlined, tr('Hisa'), () => _open(StockScreen(session: widget.session))),
            if (_shopView) item(Icons.account_balance_wallet_outlined, tr('Fedha'), () => _open(FinanceScreen(session: widget.session))),
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
      if (_shopView)
        _MoreItem('day', Icons.health_and_safety_outlined, tr('Madai ya bima'), tr('Bima zinadaiwa kiasi gani, taarifa za kudai'),
            () => _open(ClaimsScreen(session: widget.session))),
      if (_can(Perm.recordExpenses))
        _MoreItem('day', Icons.receipt_long_outlined, tr('Matumizi'), tr('Kodi, umeme, mishahara… na yanayokuja'),
            () => _open(ExpensesInsightScreen(session: widget.session))),
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
        _MoreItem('day', Icons.query_stats_rounded, tr('Ripoti'), tr('Mambo ya kujua na ya kufanya: faida, 80/20, hisa, madeni'),
            () => _open(ReportScreen(session: widget.session))),
      if (_can(Perm.viewShopSales))
        _MoreItem('stock', Icons.bar_chart_rounded, tr('Fedha'), tr('Faida, matumizi, pesa iliyoingia na kutoka'),
            () => _open(FinanceScreen(session: widget.session))),
      if (_can(Perm.viewShopSales))
        _MoreItem('stock', Icons.insights_rounded, tr('Utabiri na watu'), tr('Mwezi utafika wapi, wauzaji, zilizolala'),
            () => _open(ForecastScreen(session: widget.session))),
      // Duka na watu
      if (u.isOwner || u.otherShops > 0)
        _MoreItem('shop', Icons.storefront_rounded, tr('Maduka yangu'), tr('Badili duka bila kutoka'), () => _open(MyShopsScreen(session: widget.session))),
      if (u.isOwner)
        _MoreItem('shop', Icons.admin_panel_settings_outlined, tr('Wafanyakazi'), tr('Toa au ondoa ruhusa, kwa muda au kudumu'),
            () => _open(StaffPermissionsScreen(session: widget.session))),
      if (_can(Perm.manageDevices))
        _MoreItem('shop', Icons.phonelink_lock, tr('Vifaa'), tr('Simu na kompyuta zinazoruhusiwa'), () => _open(DevicesScreen(session: widget.session))),
      _MoreItem('shop', Icons.support_agent_rounded, tr('Msaada'), tr('Uliza Saola, ona majibu'), () => _open(SupportScreen(session: widget.session))),
    ];
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _MoreScreen(items: items, onAccount: _account),
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

/// Zaidi: the rest of the app, in three groups of small tiles inside cards
/// (4 a row on a phone), with a search that narrows as you type. Personal
/// things (PIN, language, sign out) are under the avatar on home, and a
/// last card says so. A tile opens its screen on top of this page, so Back
/// returns to Zaidi.
class _MoreScreen extends StatefulWidget {
  const _MoreScreen({required this.items, required this.onAccount});

  final List<_MoreItem> items;
  final VoidCallback onAccount;

  @override
  State<_MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<_MoreScreen> {
  String _q = '';

  static const _sections = [
    ('day', 'Kila siku', Icons.today_rounded, Color(0xFF1B7F64)),
    ('stock', 'Hisa na mizigo', Icons.inventory_2_outlined, Color(0xFF2F5FC4)),
    ('shop', 'Duka na watu', Icons.groups_outlined, Color(0xFF6E5A9E)),
  ];

  /// Opens on top of Zaidi, so Back comes back here (not to home).
  void _go(_MoreItem item) {
    tick();
    item.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final shown = widget.items.where((i) => q.isEmpty || i.label.toLowerCase().contains(q) || (i.subtitle ?? '').toLowerCase().contains(q)).toList();
    var n = 0;

    return Scaffold(
      backgroundColor: pageBackground,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Row(children: [
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
                        child: const Icon(Icons.chevron_left_rounded, color: kInk),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const T('Zaidi', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: kInk, letterSpacing: -.4)),
                ]),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (v) => setState(() => _q = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: tr('Tafuta: mf. madeni, wateja, agiza…'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: cardColor,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                AnimatedSize(
                  duration: Motion.of(context, Motion.base),
                  curve: Motion.curve,
                  alignment: Alignment.topCenter,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final (key, title, icon, colour) in _sections)
                      if (shown.any((i) => i.section == key))
                        Appear(
                          index: n++,
                          child: _section(tr(title), icon, colour, shown.where((i) => i.section == key).toList()),
                        ),
                    if (shown.isEmpty)
                      Padding(padding: const EdgeInsets.all(32), child: Center(child: T('Hakuna kinacholingana.', style: const TextStyle(color: mutedText)))),
                  ]),
                ),
                if (q.isEmpty) ...[
                  const SizedBox(height: 14),
                  Appear(
                    index: n++,
                    child: Material(
                      color: const Color(0xFFE7F6EF),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onAccount();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            const Icon(Icons.account_circle_outlined, color: Color(0xFF0E5A44)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: T('PIN, lugha na kutoka viko kwenye akaunti yako: gusa picha yako juu ya Nyumbani.',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF0E5A44), height: 1.35)),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF0E5A44)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, IconData icon, Color colour, List<_MoreItem> items) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            Icon(icon, size: 17, color: colour),
            const SizedBox(width: 8),
            Text(title.toUpperCase(), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: mutedText)),
          ]),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= 640 ? 6 : 4;
          final w = box.maxWidth / cols;
          return Wrap(children: [for (final item in items) SizedBox(width: w, child: _tile(item, colour))]);
        }),
      ]),
    );
  }

  Widget _tile(_MoreItem item, Color colour) {
    return Tooltip(
      message: item.subtitle ?? item.label,
      child: Semantics(
        button: true,
        label: item.label,
        excludeSemantics: true,
        child: Pressable(
          onTap: () => _go(item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: colour.withValues(alpha: .10), borderRadius: BorderRadius.circular(16)),
                child: Icon(item.icon, color: colour, size: 23),
              ),
              const SizedBox(height: 7),
              Text(item.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, height: 1.2, color: kInk)),
            ]),
          ),
        ),
      ),
    );
  }
}
