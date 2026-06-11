import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/app_transaction.dart';
import '../models/category.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../utils/calculator.dart';
import '../utils/format.dart';
import '../widgets/calculator_keypad.dart';

class AddTransactionScreen extends StatefulWidget {
  /// When non-null, the screen edits this existing transaction instead of
  /// creating a new one.
  final AppTransaction? editing;

  const AddTransactionScreen({super.key, this.editing});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  static const _operators = '+−×÷';

  String _type = 'expense';
  String _expr = '';
  List<Category> _allCategories = [];
  int? _selectedCategoryId;
  DateTime _date = DateTime.now();
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _type = e.type;
      _expr = _formatNum(e.amount);
      _selectedCategoryId = e.categoryId;
      _date = e.date;
      _noteController.text = e.note;
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final cats = await DatabaseHelper.instance.getCategories();
    setState(() => _allCategories = cats);
  }

  List<Category> get _categories =>
      _allCategories.where((c) => c.type == _type).toList();

  Color get _accent => _type == 'expense' ? expenseColor : incomeColor;

  double? get _amount => evaluateExpression(_expr);

  bool get _hasOperator => _expr.split('').any(_operators.contains);

  // ---- Keypad handling ----

  void _onKey(String key) {
    setState(() {
      if (key == 'C') {
        _expr = '';
      } else if (key == '⌫') {
        if (_expr.isNotEmpty) {
          _expr = _expr.substring(0, _expr.length - 1);
        }
      } else if (key == '=') {
        final v = evaluateExpression(_expr);
        if (v != null) _expr = _formatNum(v);
      } else if (_operators.contains(key)) {
        if (_expr.isEmpty) return; // don't start with an operator
        final last = _expr[_expr.length - 1];
        if (_operators.contains(last)) {
          _expr = _expr.substring(0, _expr.length - 1) + key; // swap operator
        } else {
          _expr += key;
        }
      } else if (key == '.') {
        if (!_currentNumber().contains('.')) {
          final last = _expr.isEmpty ? '' : _expr[_expr.length - 1];
          _expr += (_expr.isEmpty || _operators.contains(last)) ? '0.' : '.';
        }
      } else {
        _expr += key; // a digit
      }
    });
  }

  /// The trailing run of digits/decimal point (the number currently being typed).
  String _currentNumber() {
    var i = _expr.length - 1;
    final chars = <String>[];
    while (i >= 0 && '0123456789.'.contains(_expr[i])) {
      chars.add(_expr[i]);
      i--;
    }
    return chars.reversed.join();
  }

  String _formatNum(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  // ---- Date ----

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    setState(() {
      _date = DateTime(
        d.year,
        d.month,
        d.day,
        t?.hour ?? _date.hour,
        t?.minute ?? _date.minute,
      );
    });
  }

  // ---- Save ----

  Future<void> _save() async {
    final amount = _amount;
    if (amount == null || amount <= 0) {
      _toast('Enter a valid amount greater than 0');
      return;
    }
    if (_selectedCategoryId == null) {
      _toast('Pick a category');
      return;
    }
    final txn = AppTransaction(
      id: widget.editing?.id,
      type: _type,
      amount: amount,
      categoryId: _selectedCategoryId!,
      date: _date,
      note: _noteController.text.trim(),
    );
    if (widget.editing != null) {
      await DatabaseHelper.instance.updateTransaction(txn);
    } else {
      await DatabaseHelper.instance.insertTransaction(txn);
      if (_type == 'expense') await _maybeBudgetAlert(amount);
    }
    if (mounted) Navigator.pop(context, true);
  }

  /// After saving a new expense, alert if it pushed the category to 80% or
  /// 100% of its (effective) budget for that month.
  Future<void> _maybeBudgetAlert(double amount) async {
    final catId = _selectedCategoryId!;
    final year = _date.year;
    final month = _date.month;
    final limit =
        await DatabaseHelper.instance.effectiveLimit(catId, year, month);
    if (limit == null || limit <= 0) return;

    final after = await DatabaseHelper.instance
        .getCategoryMonthSpending(catId, year, month);
    final before = after - amount;
    final catName = _allCategories.firstWhere((c) => c.id == catId).name;

    String title;
    String body;
    if (before < limit && after >= limit) {
      title = 'Over budget: $catName';
      body =
          "You've spent ${formatRM(after)} of your ${formatRM(limit)} budget this month.";
    } else if (before < limit * 0.8 && after >= limit * 0.8) {
      title = 'Budget warning: $catName';
      body =
          "You've used ${(after / limit * 100).round()}% (${formatRM(after)} of ${formatRM(limit)}) this month.";
    } else {
      return; // no threshold newly crossed
    }

    await NotificationService.instance.showBudgetAlert(title: title, body: body);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This transaction will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: expenseColor)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseHelper.instance.deleteTransaction(widget.editing!.id!);
    if (mounted) Navigator.pop(context, true);
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.editing == null ? 'Add Transaction' : 'Edit Transaction'),
        actions: [
          if (widget.editing != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'expense',
                      label: Text('Expense'),
                      icon: Icon(Icons.south_west)),
                  ButtonSegment(
                      value: 'income',
                      label: Text('Income'),
                      icon: Icon(Icons.north_east)),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() {
                  _type = s.first;
                  _selectedCategoryId = null;
                }),
              ),
            ),
            _amountDisplay(),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Category',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _categoryChips(),
                    const SizedBox(height: 16),
                    const Text('When',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    _dateRow(),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              color: const Color(0xFFEDEFED),
              padding: const EdgeInsets.all(6),
              child: CalculatorKeypad(onKey: _onKey, accent: _accent),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Save', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountDisplay() {
    final preview = _amount;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _expr.isEmpty ? 'RM 0' : 'RM $_expr',
            style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.bold, color: _accent),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (_hasOperator && preview != null)
            Text('= ${formatRM(preview)}',
                style: const TextStyle(fontSize: 16, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _categoryChips() {
    if (_categories.isEmpty) return const Text('No categories');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _categories.map((c) {
        final selected = c.id == _selectedCategoryId;
        return ChoiceChip(
          label: Text('${c.icon} ${c.name}'),
          selected: selected,
          onSelected: (_) => setState(() => _selectedCategoryId = c.id),
          selectedColor: _accent.withValues(alpha: 0.18),
        );
      }).toList(),
    );
  }

  Widget _dateRow() {
    return Row(
      children: [
        Expanded(child: Text(formatDate(_date))),
        TextButton.icon(
          onPressed: () => setState(() => _date = DateTime.now()),
          icon: const Icon(Icons.access_time, size: 18),
          label: const Text('Now'),
        ),
        TextButton.icon(
          onPressed: _pickDateTime,
          icon: const Icon(Icons.edit_calendar, size: 18),
          label: const Text('Pick'),
        ),
      ],
    );
  }
}
