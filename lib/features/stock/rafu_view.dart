import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/units.dart';
import '../../core/smooth.dart';
import 'stock_look.dart';

const _ink = Color(0xFF14211D);
const _muted = Color(0xFF5B6F69);
const _primary = Color(0xFF12644E);

/// Rafu: the shop as aisles of shelves, drawn from the same products as the
/// list (no second request). Each category is an aisle; each product a bay
/// with up to 3 packs drawn in its form (3 plenty, 2 fine, 1 low, a dashed
/// ghost when out). "Muda" recolours the packs by expiry.
///
/// Search keeps only what matches (and says where); the aisle strip jumps to
/// an aisle. A bay opens a sheet with what matters and what to do next.
class RafuView extends StatefulWidget {
  const RafuView({
    super.key,
    required this.products,
    required this.categories,
    required this.mode,
    required this.search,
    required this.query,
    required this.onRefresh,
    required this.onOpen,
    this.onReceive,
    this.onReorder,
  });

  final List<Map<String, dynamic>> products;
  final Map<int, String> categories;
  final String mode; // hisa | muda
  final Widget search;
  final String query;
  final Future<void> Function() onRefresh;
  final void Function(Map<String, dynamic>) onOpen;
  final VoidCallback? onReceive;
  final VoidCallback? onReorder;

  @override
  State<RafuView> createState() => _RafuViewState();
}

class _Aisle {
  _Aisle(this.id, this.name, this.items);
  final int id;
  final String name;
  final List<Map<String, dynamic>> items;
  int get gaps => items.where((p) => p['is_out'] == true).length;
  double get fill => items.isEmpty ? 0 : 1 - gaps / items.length;
}

class _RafuViewState extends State<RafuView> {
  final _keys = <int, GlobalKey>{};
  int? _current;

  List<_Aisle> get _aisles {
    final by = <int, List<Map<String, dynamic>>>{};
    for (final p in widget.products) {
      by.putIfAbsent(asInt(p['category_id']), () => []).add(p);
    }
    final order = [...widget.categories.keys.where(by.containsKey), if (by.containsKey(0)) 0];
    return [
      for (final id in order)
        _Aisle(id, id == 0 ? tr('Bila aina') : widget.categories[id]!, by[id]!..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()))),
    ];
  }

  void _jump(int id) {
    tick();
    setState(() => _current = id);
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: Motion.of(context, Motion.base), curve: Motion.curve);
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.query.trim().toLowerCase();
    final aisles = _aisles;
    final shown = [
      for (final a in aisles)
        if (q.isEmpty) a else _Aisle(a.id, a.name, a.items.where((p) => '${p['name']}'.toLowerCase().contains(q)).toList()),
    ].where((a) => a.items.isNotEmpty).toList();
    final hits = shown.fold<int>(0, (s, a) => s + a.items.length);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 10), child: widget.search),
      AnimatedSwitcher(
        duration: Motion.of(context, Motion.fast),
        child: q.isEmpty
            ? SizedBox(key: const ValueKey('rail'), height: 72, child: _rail(aisles))
            : Padding(
                key: const ValueKey('found'),
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Text(
                  hits == 0 ? tr('Hakuna kinacholingana na ":q"', {'q': widget.query.trim()}) : tr('Imepatikana :n kwenye rafu :a', {'n': hits, 'a': shown.length}),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: hits == 0 ? _muted : _primary),
                ),
              ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: widget.onRefresh,
          // All aisles built at once (a shop has a handful; each shows 2 rows
          // until opened), so the aisle strip can jump to any of them.
          child: SingleChildScrollView(
            key: const PageStorageKey('stock-rafu'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final a in shown)
                Padding(
                  key: _keys.putIfAbsent(a.id, GlobalKey.new),
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _AisleCard(aisle: a, mode: widget.mode, searching: q.isNotEmpty, onBay: _sheet),
                ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _rail(List<_Aisle> aisles) {
    // The strip scrolls; its right edge fades out instead of slicing a card,
    // which reads as "more this way".
    return ShaderMask(
      shaderCallback: (r) => const LinearGradient(
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, .88, 1],
      ).createShader(r),
      blendMode: BlendMode.dstIn,
      child: _railList(aisles),
    );
  }

  Widget _railList(List<_Aisle> aisles) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: aisles.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final a = aisles[i];
        final on = _current == a.id;
        return Semantics(
          button: true,
          label: '${a.name}, ${tr('bidhaa :n', {'n': a.items.length})}',
          child: Pressable(
            onTap: () => _jump(a.id),
            child: AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              width: 128,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: on ? const Color(0xFFE7F6EF) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: on ? _primary : const Color(0xFFDCE5E1), width: 1.5),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
                const SizedBox(height: 2),
                Text(
                  a.gaps > 0 ? tr('bidhaa :n · mapengo :g', {'n': a.items.length, 'g': a.gaps}) : tr('bidhaa :n', {'n': a.items.length}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: a.fill,
                    minHeight: 4,
                    backgroundColor: const Color(0xFFEEF3F1),
                    color: a.fill < .8 ? const Color(0xFFE39B2E) : const Color(0xFF1F8A66),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  void _sheet(Map<String, dynamic> p) {
    tick();
    final days = daysToExpiry(p);
    final exp = parseDate(p['next_expiry']);
    final units = unitsOf(p);
    final cat = widget.categories[asInt(p['category_id'])] ?? tr('Bila aina');
    Widget info(String k, String v) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF5F8F7), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k, style: const TextStyle(fontSize: 11, color: _muted)),
              const SizedBox(height: 2),
              Text(v, maxLines: 2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
            ]),
          ),
        );
    Widget action(IconData icon, String label, VoidCallback onTap, {bool primary = false}) => Expanded(
          child: Pressable(
            onTap: onTap,
            child: Container(
              height: 68,
              decoration: BoxDecoration(color: primary ? _primary : const Color(0xFFF2F6F4), borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: primary ? Colors.white : _ink, size: 21),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary ? Colors.white : _ink)),
              ]),
            ),
          ),
        );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheet) {
        void go(VoidCallback f) {
          Navigator.of(sheet).pop();
          f();
        }

        final look = stateLooks[stateOf(p)]!;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                PackIcon(form: '${p['form'] ?? ''}', color: look.ink, size: 30, empty: p['is_out'] == true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p['name']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: _ink)),
                    const SizedBox(height: 2),
                    Text('$cat · ${stockText(p)}', style: const TextStyle(fontSize: 13, color: _muted)),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: look.soft, borderRadius: BorderRadius.circular(99)),
                  child: Text(tr(look.label), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: look.ink)),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                info(tr('Kiwango cha chini'), asInt(p['reorder_level']) > 0 ? describeStock(asInt(p['reorder_level']), units) : '—'),
                const SizedBox(width: 8),
                info(tr('Inaisha'), exp == null ? '—' : (days != null && days < 0 ? tr('imeisha muda') : '${exp.day}/${exp.month}/${exp.year}')),
                const SizedBox(width: 8),
                info(tr('Bei'), mainPrice(p)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                action(Icons.open_in_full_rounded, tr('Fungua'), () => go(() => widget.onOpen(p)), primary: widget.onReceive == null),
                if (widget.onReceive != null) ...[const SizedBox(width: 8), action(Icons.local_shipping_outlined, tr('Pokea'), () => go(widget.onReceive!), primary: true)],
                if (widget.onReorder != null) ...[const SizedBox(width: 8), action(Icons.shopping_cart_checkout_rounded, tr('Agiza'), () => go(widget.onReorder!))],
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _AisleCard extends StatefulWidget {
  const _AisleCard({required this.aisle, required this.mode, required this.searching, required this.onBay});
  final _Aisle aisle;
  final String mode;
  final bool searching;
  final void Function(Map<String, dynamic>) onBay;

  @override
  State<_AisleCard> createState() => _AisleCardState();
}

class _AisleCardState extends State<_AisleCard> {
  static const _perRow = 3;
  static const _rowsShown = 2;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.aisle;
    final showAll = _all || widget.searching;
    final items = showAll ? a.items : a.items.take(_perRow * _rowsShown).toList();
    final rows = <List<Map<String, dynamic>>>[
      for (var i = 0; i < items.length; i += _perRow) items.sublist(i, (i + _perRow).clamp(0, items.length)),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Text(a.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink))),
          Text(
            a.gaps > 0 ? tr('bidhaa :n · mapengo :g', {'n': a.items.length, 'g': a.gaps}) : tr('bidhaa :n', {'n': a.items.length}),
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ]),
        const SizedBox(height: 10),
        AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.curve,
          alignment: Alignment.topCenter,
          child: Column(children: [
            for (var r = 0; r < rows.length; r++) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var c = 0; c < _perRow; c++)
                  Expanded(
                    child: c < rows[r].length
                        ? _Bay(product: rows[r][c], mode: widget.mode, order: r * _perRow + c, onTap: () => widget.onBay(rows[r][c]))
                        : const SizedBox.shrink(),
                  ),
              ]),
              // The plank the packs stand on.
              Container(
                height: 8,
                margin: const EdgeInsets.only(top: 3, bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFC9A87C),
                  borderRadius: BorderRadius.circular(3),
                  border: const Border(bottom: BorderSide(color: Color(0xFFA9875B), width: 2)),
                ),
              ),
            ],
          ]),
        ),
        if (!widget.searching && a.items.length > _perRow * _rowsShown)
          TextButton(
            onPressed: () {
              tick();
              setState(() => _all = !_all);
            },
            child: Text(_all ? tr('Onyesha chache') : tr('Onyesha zote :n', {'n': a.items.length})),
          ),
      ]),
    );
  }
}

class _Bay extends StatelessWidget {
  const _Bay({required this.product, required this.mode, required this.order, required this.onTap});
  final Map<String, dynamic> product;
  final String mode;
  final int order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final n = packsOf(p);
    final Color color;
    if (mode == 'muda') {
      color = expiryColor(p);
    } else {
      color = n == 1 ? const Color(0xFFC98418) : const Color(0xFF1F8A66);
    }
    final packs = Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
      if (n == 0)
        const PackIcon(form: 'other', color: Color(0xFFC2412D), size: 22, empty: true)
      else
        for (var i = 0; i < n; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: PackIcon(form: '${p['form'] ?? ''}', color: color, size: 22, fill: Color.lerp(color, Colors.white, .72)),
          ),
    ]);
    return Semantics(
      button: true,
      label: '${p['name']}, ${stockText(p)}',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 34,
              child: Align(
                alignment: Alignment.bottomCenter,
                // Packs drop onto the shelf when the aisle first appears (or the mode changes).
                child: _Drop(key: ValueKey('$mode${p['id']}'), order: order, child: packs),
              ),
            ),
            if (n == 0)
              Text(p['never_stocked'] == true ? tr('MPYA') : tr('TUPU'),
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: p['never_stocked'] == true ? const Color(0xFF2F5FC4) : const Color(0xFFA8321F))),
            const SizedBox(height: 4),
            SizedBox(
              height: 30,
              child: Text('${p['name']}', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, height: 1.25, fontWeight: FontWeight.w600, color: _ink)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Drop extends StatelessWidget {
  const _Drop({super.key, required this.order, required this.child});
  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Duration(milliseconds: 260 + (order < 9 ? order * 35 : 0)));
    if (d == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: d,
      curve: Curves.easeOutBack,
      builder: (_, v, c) => Opacity(opacity: v.clamp(0, 1), child: Transform.translate(offset: Offset(0, (1 - v) * -10), child: c)),
      child: child,
    );
  }
}
