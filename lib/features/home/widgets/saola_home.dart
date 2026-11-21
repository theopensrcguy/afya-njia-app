import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/i18n.dart';
import '../../../core/session.dart';
import '../../../core/smooth.dart';
import '../../saola/saola_desk.dart';
import '../../saola/saola_parts.dart';
import '../../saola/saola_shops.dart';

/// Home for Saola's own workspace (v0.46.1; a console since v0.48.3). Not a
/// shop: how the system is doing (who is using it today, errors, what waits),
/// and every card opens its work IN THE APP: shops, one shop, new-shop
/// requests, support. Only the shared catalogue and the map are still on the
/// web, and they say so.
class SaolaHome extends StatefulWidget {
  const SaolaHome({super.key, required this.session, required this.refreshTick, required this.onSwitchShop});

  final Session session;
  final int refreshTick;
  final VoidCallback onSwitchShop;

  @override
  State<SaolaHome> createState() => _SaolaHomeState();
}

class _SaolaHomeState extends State<SaolaHome> {
  Map<String, dynamic>? _d;
  String? _error;
  String _chart = 'sales';

  ApiClient get _api => widget.session.api;

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
      final d = await _api.get('saola/summary') as Map<String, dynamic>;
      if (mounted) setState(() => (_d = d, _error = null));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _go(Widget page) async {
    tick();
    await Navigator.of(context).push(riseRoute(page));
    _load();
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
    final v = ((d['vitals'] as Map?) ?? const {}).cast<String, dynamic>();
    final bill = ((d['billing'] as Map?) ?? const {}).cast<String, dynamic>();
    final links = ((d['links'] as Map?) ?? const {}).cast<String, dynamic>();
    final trend = ((d['trend'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final follow = ((d['follow'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final shops = asInt(t['shops']);
    final active = asInt(t['active']);
    final s = widget.session;

    final req7 = asInt(v['requests_7d']), err7 = asInt(v['errors_7d']);
    final rate = req7 == 0 ? 0.0 : err7 * 100 / req7;
    final failed = v['failed_jobs'] == null ? 0 : asInt(v['failed_jobs']);
    final healthy = rate < 1 && failed == 0;
    final oldest = v['oldest_ticket_hours'] == null ? null : asInt(v['oldest_ticket_hours']);
    final owing = asInt(bill['grace']) + asInt(bill['expired']);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: staggered([
      // Dark card: the shops, and who is on today.
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [sDeep, Color(0xFF145244)]),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: sMint.withValues(alpha: .18), borderRadius: BorderRadius.circular(99)),
              child: Text(tr('Msimamizi wa Saola'), style: const TextStyle(color: sMint, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
            const Spacer(),
            const _LiveDot(),
            const SizedBox(width: 6),
            Text(tr('Leo'), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          Pressable(
            onTap: () => _go(SaolaShopsScreen(session: s)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              CountUp(value: shops, format: (v) => '$v', style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(tr('maduka yanatumia Afya Njia'), style: const TextStyle(color: Colors.white70, fontSize: 13))),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ]),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: shops == 0 ? 0 : active / shops),
              duration: Motion.of(context, Motion.slow),
              curve: Motion.curve,
              builder: (_, x, _) => LinearProgressIndicator(value: x, minHeight: 8, backgroundColor: Colors.white12, valueColor: const AlwaysStoppedAnimation(sMint)),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 18, runSpacing: 8, children: [
            _dot(sMint, tr('Hai'), active),
            _dot(const Color(0xFF8FB3FF), tr('Inaanza'), asInt(t['starting'])),
            _dot(const Color(0xFFF2B36B), tr('Ya kufuatilia'), asInt(t['follow_up'])),
            if (asInt(t['paused']) > 0) _dot(const Color(0xFFE88A7A), tr('Imesimamishwa'), asInt(t['paused'])),
          ]),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white12),
          const SizedBox(height: 14),
          Row(children: [
            _today(tr('Maduka leo'), asInt(v['shops_today'])),
            _today(tr('Watu leo'), asInt(v['people_today'])),
            _today(tr('Mauzo leo'), asInt(v['sales_today'])),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      // Afya ya mfumo: is the system itself fine?
      sCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            AnimatedContainer(
              duration: Motion.of(context, Motion.base),
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: healthy ? const Color(0xFFE7F6EF) : const Color(0xFFFFF4DC), borderRadius: BorderRadius.circular(12)),
              child: Icon(healthy ? Icons.monitor_heart_outlined : Icons.warning_amber_rounded, color: healthy ? sGood : sWarn, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Afya ya mfumo'), style: const TextStyle(fontWeight: FontWeight.w800, color: sInk)),
                Text(healthy ? tr('Kila kitu kiko sawa') : tr('Kuna hitilafu za kuangalia'),
                    style: TextStyle(fontSize: 12, color: healthy ? sGood : sWarn, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _vital(tr('Maombi leo'), groupDigits0(asInt(v['requests_today']))),
            _vital(tr('Hitilafu leo'), '${asInt(v['errors_today'])}', bad: asInt(v['errors_today']) > 0),
            _vital(tr('Kiwango, siku 7'), '${rate.toStringAsFixed(rate < 1 ? 2 : 1)}%', bad: rate >= 1),
            if (v['failed_jobs'] != null) _vital(tr('Kazi zilizoshindwa'), '$failed', bad: failed > 0),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      sCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(tr('Maduka yote, siku 14'), style: const TextStyle(fontWeight: FontWeight.w800, color: sInk))),
            SizedBox(
              width: 190,
              child: SlidingSegments<String>(
                values: const ['sales', 'requests'],
                labels: [tr('Mauzo'), tr('Matumizi')],
                selected: _chart,
                height: 34,
                fontSize: 12.5,
                onChanged: (x) {
                  tick();
                  setState(() => _chart = x);
                },
              ),
            ),
          ]),
          const SizedBox(height: 14),
          DayBars(days: trend, valueKey: _chart, errorKey: _chart == 'requests' ? 'errors' : null, color: _chart == 'sales' ? sGood : const Color(0xFF2F5FC4)),
        ]),
      ),
      sHeading(tr('Kazi zinazosubiri')),
      Row(children: [
        Expanded(
          child: _task(Icons.support_agent_rounded, tr('Msaada'), asInt(w['tickets']),
              asInt(w['urgent_tickets']) > 0
                  ? tr('dharura :n', {'n': asInt(w['urgent_tickets'])})
                  : (oldest == null ? tr('Hakuna anayesubiri') : tr('wa zamani: saa :n', {'n': oldest})),
              asInt(w['urgent_tickets']) > 0 || (oldest != null && oldest >= 24),
              () => _go(SaolaTicketsScreen(session: s))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _task(Icons.add_business_outlined, tr('Maduka mapya'), asInt(w['shop_requests']), tr('maombi ya kukagua'), false,
              () => _go(SaolaRequestsScreen(session: s))),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _task(Icons.phone_in_talk_outlined, tr('Ya kufuatilia'), asInt(t['follow_up']), tr('hayauzi wiki hii'), false,
              () => _go(SaolaShopsScreen(session: s, filter: 'fuatilia'))),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _task(Icons.payments_outlined, tr('Malipo'), owing,
              tr('majaribio :a · wamelipa :b', {'a': asInt(bill['trial']), 'b': asInt(bill['paid'])}), owing > 0,
              () => _go(SaolaShopsScreen(session: s, filter: 'kulipa'))),
        ),
      ]),
      if (asInt(v['devices_waiting']) > 0) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFFF4DC), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const Icon(Icons.phonelink_lock_outlined, color: sWarn, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Vifaa :n vinasubiri idhini kwenye maduka. Mmiliki huidhinisha; Saola husaidia mmiliki tu.', {'n': asInt(v['devices_waiting'])}),
                  style: const TextStyle(color: sWarn, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ],
      sHeading(tr('Ya kupigia simu wiki hii'), trailing: TextButton(onPressed: () => _go(SaolaShopsScreen(session: s)), child: Text(tr('Yote')))),
      if (follow.isEmpty)
        sCard(child: Text(tr('Maduka yote yanauza. Hakuna wa kufuatilia.'), style: const TextStyle(color: sMuted)))
      else
        for (final f in follow)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Pressable(
              onTap: () => _go(SaolaShopScreen(session: s, id: asInt(f['id']), name: '${f['name']}')),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  Hero(
                    tag: 'saola-shop-${f['id']}',
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: statusLook('${f['status']}').$2, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.storefront_rounded, size: 20, color: statusLook('${f['status']}').$1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: sInk)),
                      Text(
                        [
                          '${f['status_label']}',
                          if (f['last_sale_days'] != null) tr('mauzo ya mwisho siku :n zilizopita', {'n': '${f['last_sale_days']}'}) else tr('haijauza bado'),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: sMuted),
                      ),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: sMuted),
                ]),
              ),
            ),
          ),
      sHeading(tr('Kwenye wavuti')),
      Row(children: [
        Expanded(child: _web(Icons.medication_outlined, tr('Orodha ya dawa'), links['orodha'] as String?)),
        const SizedBox(width: 10),
        Expanded(child: _web(Icons.map_outlined, tr('Ramani ya maduka'), links['ramani'] as String?)),
      ]),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: widget.onSwitchShop,
        icon: const Icon(Icons.swap_horiz_rounded),
        label: Text(tr('Fanya kazi kwenye duka (Maduka yangu)')),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: const StadiumBorder()),
      ),
      const SizedBox(height: 8),
      Text(tr('Namba tu: idadi ya mauzo, watu na vifaa. Pesa, wateja na hisa ya duka ni siri yao.'),
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: sMuted)),
    ]));
  }

  Widget _dot(Color c, String label, int n) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label $n', style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]);

  Widget _today(String label, int n) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CountUp(value: n, format: groupDigits0, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
        ]),
      );

  Widget _vital(String label, String value, {bool bad = false}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, maxLines: 1, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: bad ? sBad : sInk)),
          const SizedBox(height: 2),
          Text(label, maxLines: 2, style: const TextStyle(fontSize: 11, color: sMuted, height: 1.2)),
        ]),
      );

  Widget _task(IconData icon, String title, int n, String note, bool hot, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: Container(
          height: 128,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: hot ? const Color(0xFFFFF4DC) : const Color(0xFFEFF4F2), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 18, color: hot ? sWarn : sDeep),
              ),
              const Spacer(),
              AnimatedScale(
                scale: n > 0 ? 1 : .9,
                duration: Motion.of(context, Motion.base),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: n > 0 ? sDeep : const Color(0xFFEEF3F1), borderRadius: BorderRadius.circular(99)),
                  child: Text('$n', style: TextStyle(color: n > 0 ? sMint : sMuted, fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
              ),
            ]),
            const Spacer(),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: sInk, fontSize: 14.5)),
            const SizedBox(height: 2),
            Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: hot ? sWarn : sMuted)),
          ]),
        ),
      );

  Widget _web(IconData icon, String label, String? url) => Pressable(
        onTap: url == null
            ? null
            : () {
                tick();
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .6), borderRadius: BorderRadius.circular(18), border: Border.all(color: sLine)),
          child: Row(children: [
            Icon(icon, size: 19, color: sMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: sInk, fontSize: 13))),
            const Icon(Icons.open_in_new_rounded, size: 15, color: sMuted),
          ]),
        ),
      );
}

/// A soft pulsing dot: "live, today".
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .35, end: 1.0).animate(_c),
        child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: sMint, shape: BoxShape.circle)),
      );
}
