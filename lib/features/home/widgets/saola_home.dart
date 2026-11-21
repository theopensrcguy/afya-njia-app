import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/money.dart';
import '../../../core/smooth.dart';
import '../../insights/insight_parts.dart' show kDeep, kInk, kMint, kMuted;

/// Home for Saola's own workspace (v0.46.1). It is not a shop, so there are
/// no sales, no stock, no Uza here: how many shops use Afya Njia, which ones
/// need a call this week, and what waits for Saola. The work itself is on the
/// web panel; each card opens its page there. To work in a real shop, switch
/// to it (Maduka yangu).
class SaolaHome extends StatefulWidget {
  const SaolaHome({super.key, required this.api, required this.refreshTick, required this.onSwitchShop});

  final ApiClient api;
  final int refreshTick;
  final VoidCallback onSwitchShop;

  @override
  State<SaolaHome> createState() => _SaolaHomeState();
}

class _SaolaHomeState extends State<SaolaHome> {
  Map<String, dynamic>? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SaolaHome old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.get('saola/summary') as Map<String, dynamic>;
      if (mounted) setState(() => (_d = d, _error = null));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _web(String? url) async {
    if (url == null) return;
    tick();
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, textAlign: TextAlign.center)),
      );
    }
    final t = (d['totals'] as Map).cast<String, dynamic>();
    final w = (d['waiting'] as Map).cast<String, dynamic>();
    final links = (d['links'] as Map).cast<String, dynamic>();
    final follow = ((d['follow'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final s7 = asInt(t['sales_7d']), p7 = asInt(t['sales_prev_7d']);
    final shops = asInt(t['shops']);
    final active = asInt(t['active']);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: staggered([
      // The dark card: shops and how many are alive.
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: kDeep, borderRadius: BorderRadius.circular(26)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: kMint.withValues(alpha: .18), borderRadius: BorderRadius.circular(99)),
              child: Text(tr('Msimamizi wa Saola'), style: const TextStyle(color: kMint, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            CountUp(value: shops, format: (v) => '$v', style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, height: 1)),
            const SizedBox(width: 8),
            Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(tr('maduka yanatumia Afya Njia'), style: const TextStyle(color: Colors.white70, fontSize: 13))),
          ]),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: shops == 0 ? 0 : active / shops,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(kMint),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 18, runSpacing: 8, children: [
            _dot(kMint, tr('Hai'), active),
            _dot(const Color(0xFF8FB3FF), tr('Inaanza'), asInt(t['starting'])),
            _dot(const Color(0xFFF2B36B), tr('Ya kufuatilia'), asInt(t['follow_up'])),
            if (asInt(t['paused']) > 0) _dot(const Color(0xFFE88A7A), tr('Imesimamishwa'), asInt(t['paused'])),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _stat(Icons.receipt_long_rounded, tr('Mauzo, siku 7'), groupDigits(s7), s7 - p7)),
        const SizedBox(width: 12),
        Expanded(child: _stat(Icons.inbox_rounded, tr('Maombi ya maduka'), '${asInt(w['shop_requests'])}', null, onTap: () => _web(links['maombi'] as String?))),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _stat(Icons.support_agent_rounded, tr('Msaada unasubiri'), '${asInt(w['tickets'])}', null, onTap: () => _web(links['msaada'] as String?))),
        const SizedBox(width: 12),
        Expanded(child: _stat(Icons.map_outlined, tr('Ramani ya maduka'), tr('Fungua'), null, onTap: () => _web(links['ramani'] as String?))),
      ]),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: Text(tr('Ya kupigia simu wiki hii'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kInk))),
        TextButton(onPressed: () => _web(links['maduka'] as String?), child: Text(tr('Yote'))),
      ]),
      if (follow.isEmpty)
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Text(tr('Maduka yote yanauza. Hakuna wa kufuatilia.'), style: const TextStyle(color: kMuted)),
        )
      else
        for (final f in follow)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: f['status'] == 'imelala' ? const Color(0xFFFBE9E5) : const Color(0xFFFFF4DC), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.storefront_rounded, size: 20, color: f['status'] == 'imelala' ? const Color(0xFFC2412D) : const Color(0xFF8A5300)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: kInk)),
                    Text(
                      [
                        '${f['status_label']}',
                        if (f['last_sale_days'] != null) tr('mauzo ya mwisho siku :n zilizopita', {'n': '${f['last_sale_days']}'}) else tr('haijauza bado'),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: kMuted),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: widget.onSwitchShop,
        icon: const Icon(Icons.swap_horiz_rounded),
        label: Text(tr('Fanya kazi kwenye duka (Maduka yangu)')),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      ),
      const SizedBox(height: 6),
      Text(tr('Hii si duka: mauzo, hisa na Uza ziko kwenye maduka yenyewe. Kazi za Saola zinafunguka kwenye wavuti.'),
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: kMuted)),
    ]));
  }

  Widget _dot(Color c, String label, int n) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label $n', style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]);

  Widget _stat(IconData icon, String label, String value, int? delta, {VoidCallback? onTap}) => Pressable(
        onTap: onTap ?? () {},
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: const Color(0xFFEFF4F2), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 19, color: kDeep),
              ),
              const Spacer(),
              if (delta != null && delta != 0)
                Text('${delta > 0 ? '↑' : '↓'} ${groupDigits(delta.abs())}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: delta > 0 ? const Color(0xFF1F8A66) : const Color(0xFFC2412D))),
              if (onTap != null) const Icon(Icons.open_in_new_rounded, size: 16, color: kMuted),
            ]),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kInk)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: kMuted)),
          ]),
        ),
      );
}
