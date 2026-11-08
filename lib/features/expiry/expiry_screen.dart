import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/format.dart';
import '../../core/money.dart';
import '../../core/session.dart';
import '../../core/i18n.dart';

/// Screen 3 of the mockups: batches that have expired or expire soon, with the
/// money at risk. Owner only (the server enforces that).
///
/// The groups do NOT overlap: each batch appears in exactly one. (The first
/// version had "within 30 / 60 / 90 days", so 60 repeated everything in 30,
/// and already-expired stock was mixed in with stock that can still be sold.)
class ExpiryScreen extends StatefulWidget {
  const ExpiryScreen({super.key, required this.session});

  final Session session;

  @override
  State<ExpiryScreen> createState() => _ExpiryScreenState();
}

/// One group: a name and which "days left" belong in it.
class _Band {
  const _Band(this.label, this.from, this.to, this.advice);

  final String label;
  final int from; // days left, inclusive
  final int to; // days left, inclusive
  final String advice;

  bool contains(int days) => days >= from && days <= to;
}

class _ExpiryScreenState extends State<ExpiryScreen> {
  static const _bands = [
    _Band('Zimeisha muda', -100000, 0, 'Haziuzwi. Ziondoe kwenye rafu: rudisha kwa msambazaji au andika kama hasara.'),
    _Band('Siku 1–30', 1, 30, 'Uza hizi kwanza, au rudisha kwa msambazaji sasa.'),
    _Band('Siku 31–60', 31, 60, 'Zipange mbele ya rafu ziuzwe kwanza.'),
    _Band('Siku 61–90', 61, 90, 'Fuatilia. Usiagize zaidi ya unachoweza kuuza.'),
  ];

  List<Map<String, dynamic>> _batches = []; // everything up to 90 days, fetched once
  int _selected = 1; // Siku 1–30 by default
  bool _loading = true;
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// One request for 90 days, then grouped on the phone: switching groups is
  /// instant and works even if the network is slow.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.get('dashboard/expiry', query: {'days': '90'}) as Map<String, dynamic>;
      if (!mounted) return;
      final batches = ((data['batches'] as List?) ?? const []).cast<Map<String, dynamic>>();
      setState(() {
        _batches = batches;
        // Expired stock is the most urgent: open on it when there is any.
        if (_inBand(0).isNotEmpty) _selected = 0;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _inBand(int i) =>
      _batches.where((b) => _bands[i].contains(asInt(b['days_left']))).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const T('Muda wa kuisha')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, style: const TextStyle(color: dangerRed)),
                    TextButton(onPressed: _load, child: const T('Jaribu tena')),
                  ]),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final band = _bands[_selected];
    final rows = _inBand(_selected);
    final value = rows.fold<int>(0, (sum, b) => sum + asInt(b['value_at_cost']));
    final expiredBand = _selected == 0;
    final tone = expiredBand ? dangerRed : warnAmber;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Chips wrap onto two lines on small phones, unlike a segmented bar.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _bands.length; i++)
                ChoiceChip(
                  label: Text('${tr(_bands[i].label)} (${_inBand(i).length})'),
                  selected: _selected == i,
                  selectedColor: i == 0 ? const Color(0xFFFDECEA) : null,
                  onSelected: (_) => setState(() => _selected = i),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: expiredBand ? const Color(0xFFFDECEA) : const Color(0xFFFFF6E5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(expiredBand ? tr('Thamani iliyopotea (bei ya kununua)') : tr('Thamani iliyo hatarini (bei ya kununua)'),
                      style: TextStyle(color: tone)),
                  Text(formatTsh(value), style: TextStyle(color: tone, fontSize: 24, fontWeight: FontWeight.w700)),
                  Text(tr(band.advice), style: TextStyle(color: tone, fontSize: 12)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Text(
                expiredBand ? tr('Hakuna dawa zilizoisha muda kwenye hisa.') : tr('Hakuna batch katika kundi hili.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: mutedText),
              ),
            ),
          for (final b in rows) _batchTile(b),
        ],
      ),
    );
  }

  Widget _batchTile(Map<String, dynamic> b) {
    final days = asInt(b['days_left']);
    final expired = days <= 0;
    final badgeColor = expired || days <= 14 ? dangerRed : warnAmber;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${b['product']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text(tr('Batch :a · vipande :b · :c', {'a': b['batch_number'], 'b': asInt(b['quantity']), 'c': b['expiry_date']}),
                    style: const TextStyle(fontSize: 12, color: mutedText)),
                Text(tr('Thamani :a', {'a': formatTsh(asInt(b['value_at_cost']))}), style: const TextStyle(fontSize: 12, color: mutedText)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: badgeColor.withAlpha(30), borderRadius: BorderRadius.circular(8)),
            child: Text(
              expired ? (days == 0 ? tr('Imeisha leo') : tr('Siku :a zilizopita', {'a': -days})) : tr('Siku :days', {'days': days}),
              style: TextStyle(color: badgeColor, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
