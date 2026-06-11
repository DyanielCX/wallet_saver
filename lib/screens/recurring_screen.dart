import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/category.dart';
import '../models/recurring_template.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'recurring_edit_screen.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  List<RecurringTemplate> _templates = [];
  Map<int, Category> _categories = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final templates = await DatabaseHelper.instance.getRecurringTemplates();
    final cats = await DatabaseHelper.instance.getCategories();
    setState(() {
      _templates = templates;
      _categories = {for (final c in cats) c.id!: c};
      _loading = false;
    });
  }

  Future<void> _openEdit([RecurringTemplate? t]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RecurringEditScreen(editing: t)),
    );
    if (saved == true) _load();
  }

  Future<bool> _confirmDelete() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete recurring transaction?'),
        content: const Text(
            'Future entries will stop being created. Transactions already '
            'created will stay.'),
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

  Future<void> _deleteTemplate(RecurringTemplate t) async {
    await DatabaseHelper.instance.deleteRecurring(t.id!);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Recurring transaction deleted')));
    }
  }

  String _frequencyLabel(String f) =>
      {'daily': 'Daily', 'weekly': 'Weekly', 'monthly': 'Monthly'}[f] ?? f;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring Transactions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        backgroundColor: seedGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
              ? _emptyState()
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: _templates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _tile(_templates[i]),
                ),
    );
  }

  Widget _tile(RecurringTemplate t) {
    final cat = _categories[t.categoryId];
    final isExpense = t.type == 'expense';
    final color = isExpense ? expenseColor : incomeColor;
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(),
      onDismissed: (_) => _deleteTemplate(t),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        onTap: () => _openEdit(t),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(cat?.icon ?? ''),
        ),
        title: Text(cat?.name ?? 'Unknown'),
        subtitle: Text(
          '${_frequencyLabel(t.frequency)} • next: ${DateFormat('d MMM yyyy').format(t.nextRun)}'
          '${t.note.isNotEmpty ? ' • ${t.note}' : ''}',
        ),
        trailing: Text(
          '${isExpense ? '-' : '+'} ${formatRM(t.amount)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.autorenew, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('No recurring transactions',
              style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          const Text('Add rent, salary, subscriptions, etc.'),
        ],
      ),
    );
  }
}
