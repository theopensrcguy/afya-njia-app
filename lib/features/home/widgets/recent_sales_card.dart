import 'package:flutter/material.dart';

import '../../../core/brand.dart';
import '../../../core/format.dart';
import '../../../core/money.dart';
import '../../../core/units.dart';
import '../../../core/i18n.dart';

/// "Mauzo ya karibuni": the last few sales, newest first.
///
/// Each sale is a map in one shape: {sold_at, total, payment_method, user,
/// items: [{name, quantity}]}. The owner's come ready from dashboard/today;
/// the helper's are converted from GET sales by [fromSaleJson].
class RecentSalesCard extends StatelessWidget {
  const RecentSalesCard({
    super.key,
    required this.sales,
    required this.totalCount,
    required this.hidden,
    required this.onSeeAll,
  });

  final List<Map<String, dynamic>> sales;
  final int totalCount;
  final bool hidden;
  final VoidCallback onSeeAll;

  /// GET sales returns full sales (items with nested product); make them
  /// look like dashboard/today's recent_sales so one card draws both.
  static Map<String, dynamic> fromSaleJson(Map<String, dynamic> s) => {
        'sold_at': s['sold_at'],
        'total': s['total'],
        'payment_method': s['payment_method'],
        'user': (s['user'] as Map?)?['name'] ?? '',
        'items': mergeSaleItems((s['items'] as List?) ?? const []),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
      decoration: softCard(),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: T('Mauzo ya karibuni', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              TextButton(onPressed: onSeeAll, child: Text(tr('Ona yote :total_count', {'total_count': totalCount}), style: const TextStyle(fontWeight: FontWeight.w800))),
            ],
          ),
          if (sales.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: T('Bado hakuna mauzo leo.', style: TextStyle(color: mutedText)),
            ),
          for (var i = 0; i < sales.length; i++) _row(sales[i], last: i == sales.length - 1),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> s, {required bool last}) {
    final method = '${s['payment_method']}';
    final color = paymentColors[method] ?? mintAccent;
    final time = parseDate(s['sold_at']);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: Color(0xFFE3EDE8)))),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withAlpha(36), borderRadius: BorderRadius.circular(13)),
            child: Text(time != null ? formatTime(time) : '--',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: inkColor)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(itemsSummary((s['items'] as List?) ?? const []),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                Text('${s['user']} · ${paymentLabels[method] ?? method}',
                    style: const TextStyle(fontSize: 12, color: mutedText)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(hidden ? '•••' : formatTsh(asInt(s['total'])).replaceFirst('TSh ', ''),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
