import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/brand.dart';
import '../../core/dialogs.dart';
import '../../core/units.dart';
import '../../models/product.dart';
import '../../core/i18n.dart';

/// How one product is sold: kidonge 1 · kadi 10 · boksi 100, each with a price.
///
/// The first row is the unit stock is counted in: its size is always 1.
/// Sizes are per product (Coartem's kadi is 24), so the owner types them.
class UnitsEditorScreen extends StatefulWidget {
  const UnitsEditorScreen({super.key, required this.api, required this.productId, required this.name, required this.units});

  final ApiClient api;
  final int productId;
  final String name;
  final List<ProductUnit> units;

  @override
  State<UnitsEditorScreen> createState() => _UnitsEditorScreenState();
}

/// One editable row. Owns its controllers so they're disposed with it.
/// The name is picked from a list, not typed (see [standardUnits]).
class _Row {
  _Row(this.name, int size, int price)
      : size = TextEditingController(text: size == 0 ? '' : '$size'),
        price = TextEditingController(text: price == 0 ? '' : '$price');

  String name;
  final TextEditingController size;
  final TextEditingController price;

  void dispose() {
    size.dispose();
    price.dispose();
  }
}

class _UnitsEditorScreenState extends State<UnitsEditorScreen> {
  late final List<_Row> _rows = [
    for (final u in widget.units) _Row(u.name, u.baseQuantity, u.price),
    if (widget.units.isEmpty) _Row('kidonge', 1, 0),
  ];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    // Suggest the next common pack, so most of the time only the size and price change.
    final names = _rows.map((r) => r.name).toSet();
    final next = !names.contains('kadi') ? 'kadi' : (!names.contains('boksi') ? 'boksi' : '');
    setState(() => _rows.add(_Row(next, 0, 0)));
  }

  void _removeRow(int i) {
    final row = _rows.removeAt(i);
    setState(() {});
    // Dispose after this frame: the TextFields are still attached right now.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  Future<void> _save() async {
    final units = <Map<String, dynamic>>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final name = normalUnitName(r.name);
      final size = i == 0 ? 1 : int.tryParse(r.size.text.trim()) ?? 0;
      final price = int.tryParse(r.price.text.trim());
      if (name.isEmpty || size < 1 || price == null) {
        setState(() => _error = tr('Chagua kipimo, na ujaze ukubwa na bei kwa kila kimoja.'));
        return;
      }
      if (i > 0 && size == 1) {
        setState(() => _error = tr(':name: ukubwa lazima uwe zaidi ya 1.', {'name': name}));
        return;
      }
      units.add({'name': name, 'base_quantity': size, 'price': price});
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.put('products/${widget.productId}/units', {'units': units});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseName = _rows.isEmpty ? 'kidonge' : unitLabel(_rows.first.name, 2);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Vipimo · :name', {'name': widget.name})), backgroundColor: pageBackground),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            tr('Kipimo cha kwanza ndicho hisa inahesabiwa kwacho (kidonge, chupa, pakiti). Vingine ni idadi ya hicho: kadi ya vidonge 10, boksi ya vidonge 100.'),
            style: TextStyle(color: mutedText, fontSize: 13),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _rows.length; i++) _rowCard(i, baseName),
          TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: const T('Ongeza kipimo')),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: dangerRed))),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(_saving ? tr('Inahifadhi…') : tr('Hifadhi')),
          ),
        ],
      ),
    );
  }

  /// The standard units, minus ones already used on another row, plus "Nyingine…".
  Future<void> _pickName(int i) async {
    final taken = {for (var j = 0; j < _rows.length; j++) if (j != i) _rows[j].name};
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: cardColor,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (name, label) in standardUnits)
              if (!taken.contains(name))
                ListTile(
                  title: Text(label),
                  trailing: _rows[i].name == name ? const Icon(Icons.check, color: brandGreen) : null,
                  onTap: () => Navigator.of(sheet).pop(name),
                ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const T('Nyingine…'),
              subtitle: const T('Kama haipo kwenye orodha'),
              onTap: () => Navigator.of(sheet).pop(''),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    var name = picked;
    if (name.isEmpty) {
      final typed = await askText(context, title: tr('Kipimo kingine'), label: tr('Jina la kipimo'), hint: tr('mfano: roli'), required: true);
      if (typed == null || !mounted) return;
      name = normalUnitName(typed);
      if (taken.contains(name)) {
        setState(() => _error = tr('":name" tayari kipo.', {'name': name}));
        return;
      }
    }
    setState(() {
      _rows[i].name = name;
      _error = null;
    });
  }

  Widget _rowCard(int i, String baseName) {
    final r = _rows[i];
    final isBase = i == 0;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: softCard(radius: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () => _pickName(i),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: isBase ? tr('Kipimo cha hisa') : tr('Kipimo'),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                child: Text(r.name.isEmpty ? tr('Chagua') : unitLabel(r.name),
                    style: TextStyle(color: r.name.isEmpty ? mutedText : inkColor)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: isBase
                ? InputDecorator(decoration: InputDecoration(labelText: tr('Ukubwa')), child: Text('1'))
                : TextField(
                    controller: r.size,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: InputDecoration(labelText: '× $baseName'),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: r.price,
              keyboardType: TextInputType.number,
              inputFormatters: digits,
              decoration: InputDecoration(labelText: tr('Bei (TSh)')),
            ),
          ),
          if (!isBase)
            IconButton(tooltip: tr('Ondoa'), onPressed: () => _removeRow(i), icon: const Icon(Icons.close))
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}
