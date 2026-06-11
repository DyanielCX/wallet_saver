import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/category.dart';
import '../theme.dart';
import '../utils/format.dart';

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  late int _year;
  late int _month;
  List<Category> _categories = [];
  Map<int, double> _defaults = {};
  Map<int, double> _overrides = {};
  Map<int, double> _spending = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  Future<void> _load() async {
    final cats =
        await DatabaseHelper.instance.getCategories(type: 'expense');
    final defaults = await DatabaseHelper.instance.getDefaultBudgets();
    final overrides =
        await DatabaseHelper.instance.getMonthBudgets(_year, _month);
    final spending =
        await DatabaseHelper.instance.getMonthSpendingByCategory(_year, _month);
    setState(() {
      _categories = cats;
      _defaults = defaults;
      _overrides = overrides;
      _spending = spending;
      _loading = false;
    });
  }

  double? _limitFor(int categoryId) =>
      _overrides[categoryId] ?? _defaults[categoryId];

  void _changeMonth(int delta) {
    var y = _year;
    var m = _month + delta;
    if (m < 1) {
      m = 12;
      y--;
    } else if (m > 12) {
      m = 1;
      y++;
    }
    setState(() {
      _year = y;
      _month = m;
      _loading = true;
    });
    _load();
  }

  Color _ratioColor(double ratio) {
    if (ratio >= 1.0) return expenseColor; // red — over
    if (ratio >= 0.8) return Colors.orange; // warning
    return incomeColor; // green — healthy
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _monthBar(),
                _overallSummary(),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: _categories.map(_categoryTile).toList(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _monthBar() {
    final label = DateFormat('MMMM yyyy').format(DateTime(_year, _month));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left)),
          Text(label,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          IconButton(
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }

  Widget _overallSummary() {
    double totalLimit = 0;
    double totalSpent = 0;
    for (final c in _categories) {
      final limit = _limitFor(c.id!);
      if (limit != null) {
        totalLimit += limit;
        totalSpent += _spending[c.id!] ?? 0;
      }
    }
    if (totalLimit == 0) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No budgets set yet — tap a category below to set one.'),
      );
    }
    final ratio = (totalSpent / totalLimit).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total budget',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('${formatRM(totalSpent)} / ${formatRM(totalLimit)}'),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
              backgroundColor: Colors.grey.shade300,
              color: _ratioColor(totalSpent / totalLimit),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryTile(Category c) {
    final limit = _limitFor(c.id!);
    final spent = _spending[c.id!] ?? 0;
    final hasOverride = _overrides.containsKey(c.id!);

    return ListTile(
      onTap: () => _editBudget(c),
      leading: Text(c.icon, style: const TextStyle(fontSize: 22)),
      title: Row(
        children: [
          Text(c.name),
          if (hasOverride)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('this month',
                  style: TextStyle(fontSize: 10, color: Colors.black54)),
            ),
        ],
      ),
      subtitle: limit == null
          ? const Text('No budget set')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                Text(
                    '${formatRM(spent)} / ${formatRM(limit)}  (${(spent / limit * 100).round()}%)'),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: (spent / limit).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: Colors.grey.shade300,
                    color: _ratioColor(spent / limit),
                  ),
                ),
              ],
            ),
      trailing: const Icon(Icons.edit, size: 18),
    );
  }

  Future<void> _editBudget(Category c) async {
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime(_year, _month));
    final defaultCtrl = TextEditingController(
        text: _defaults[c.id!]?.toStringAsFixed(2) ?? '');
    final overrideCtrl = TextEditingController(
        text: _overrides[c.id!]?.toStringAsFixed(2) ?? '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${c.icon} ${c.name}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: defaultCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: const InputDecoration(
                labelText: 'Default monthly budget (every month)',
                prefixText: 'RM ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: overrideCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: InputDecoration(
                labelText: 'Override for $monthLabel (optional)',
                prefixText: 'RM ',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Leave a field empty to remove that limit. The override applies only to the month shown above.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await _saveBudget(c, defaultCtrl.text, overrideCtrl.text);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveBudget(
      Category c, String defaultText, String overrideText) async {
    final db = DatabaseHelper.instance;
    final id = c.id!;

    final def = double.tryParse(defaultText.trim());
    if (def != null && def > 0) {
      await db.setDefaultBudget(id, def);
    } else {
      await db.removeDefaultBudget(id);
    }

    final ovr = double.tryParse(overrideText.trim());
    if (ovr != null && ovr > 0) {
      await db.setMonthBudget(id, _year, _month, ovr);
    } else {
      await db.removeMonthBudget(id, _year, _month);
    }

    await _load();
  }
}
