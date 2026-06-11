import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/app_transaction.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'add_transaction_screen.dart';
import 'recurring_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month);
  List<DateTime> _months = [];
  List<Map<String, Object?>> _rows = []; // transactions in selected month
  double _allIncome = 0; // all-time
  double _allExpense = 0; // all-time
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _key(DateTime m) => '${m.year}-${m.month}';

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final (income, expense) = await db.getAllTimeTotals();
    final months = await db.getTransactionMonths();

    // Always include the current month and the currently-selected month so the
    // dropdown can show them even if they have no transactions.
    final now = DateTime.now();
    final set = {for (final m in months) _key(m): m};
    set[_key(DateTime(now.year, now.month))] = DateTime(now.year, now.month);
    set[_key(_selectedMonth)] = _selectedMonth;
    final monthList = set.values.toList()..sort((a, b) => a.compareTo(b));

    final start = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final end = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
    final rows = await db.getTransactionsWithCategoryBetween(start, end);

    setState(() {
      _allIncome = income;
      _allExpense = expense;
      _months = monthList;
      _rows = rows;
      _loading = false;
    });
  }

  double get _savings => _allIncome - _allExpense; // all-time running total
  double _monthSum(String type) => _rows
      .where((r) => r['type'] == type)
      .fold(0.0, (sum, r) => sum + (r['amount'] as num).toDouble());

  Future<void> _openAdd() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
    );
    if (added == true) _load();
  }

  Future<bool> _confirmDelete() async {
    final res = await showDialog<bool>(
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
    return res ?? false;
  }

  Future<void> _deleteRow(Map<String, Object?> row) async {
    await DatabaseHelper.instance.deleteTransaction(row['id'] as int);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction deleted')));
    }
  }

  final TextEditingController _searchCtrl = TextEditingController();

  // [VULN-01] CWE-89 Untrusted UI text flows straight into a concatenated
  // SQL query (DatabaseHelper.searchTransactions). User input is the taint
  // source; rawQuery is the sink.
  Future<void> _openSearch() async {
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Search'),
        content: TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(hintText: 'note or category'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _searchCtrl.text),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    if (q == null) return;
    try {
      final rows = await DatabaseHelper.instance.searchTransactions(q);
      setState(() => _rows = rows);
    } catch (e, st) {
      // [VULN-06] CWE-209 Raw exception + stack trace leaked to the UI/log.
      print('search failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Search error: $e\n$st')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet Saver'),
        actions: [
          IconButton(
            tooltip: 'Search transactions',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          IconButton(
            tooltip: 'Recurring transactions',
            icon: const Icon(Icons.event_repeat),
            onPressed: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => const RecurringScreen()),
              );
              // Recurring edits may have created new transactions — refresh.
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        backgroundColor: seedGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _summaryCard(),
                _monthSelector(),
                const Divider(height: 1),
                Expanded(child: _rows.isEmpty ? _emptyState() : _list()),
              ],
            ),
    );
  }

  Widget _summaryCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Savings', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(
              formatRM(_savings),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: _savings >= 0 ? incomeColor : expenseColor,
              ),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _stat('Income', _monthSum('income'), incomeColor),
                _stat('Expense', _monthSum('expense'), expenseColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600)),
        Text(formatRM(value),
            style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _monthSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          DropdownButton<String>(
            value: _key(_selectedMonth),
            underline: const SizedBox.shrink(),
            items: _months
                .map((m) => DropdownMenuItem(
                      value: _key(m),
                      child: Text(DateFormat('MMMM yyyy').format(m)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              final m = _months.firstWhere((x) => _key(x) == v);
              setState(() {
                _selectedMonth = m;
                _loading = true;
              });
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('No transactions in ${DateFormat('MMMM yyyy').format(_selectedMonth)}',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          const Text('Tap "Add" to record one'),
        ],
      ),
    );
  }

  Widget _list() {
    return ListView.separated(
      // Bottom padding so the last row can scroll clear of the Add button.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = _rows[i];
        final isExpense = r['type'] == 'expense';
        final color = isExpense ? expenseColor : incomeColor;
        final amount = (r['amount'] as num).toDouble();
        final date = DateTime.fromMillisecondsSinceEpoch(r['date'] as int);
        final note = (r['note'] as String?) ?? '';
        return Dismissible(
          key: ValueKey(r['id']),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDelete(),
          onDismissed: (_) => _deleteRow(r),
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          child: ListTile(
            onTap: () async {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AddTransactionScreen(editing: AppTransaction.fromMap(r)),
                ),
              );
              if (changed == true) _load();
            },
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              child: Text((r['category_icon'] as String?) ?? ''),
            ),
            title: Text((r['category_name'] as String?) ?? ''),
            subtitle: Text([
              if (note.isNotEmpty) note,
              formatDate(date),
            ].join(' • ')),
            trailing: Text(
              '${isExpense ? '-' : '+'} ${formatRM(amount)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ),
        );
      },
    );
  }
}
