import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/category.dart';
import '../models/recurring_template.dart';
import '../services/recurring_service.dart';
import '../theme.dart';

class RecurringEditScreen extends StatefulWidget {
  final RecurringTemplate? editing;
  const RecurringEditScreen({super.key, this.editing});

  @override
  State<RecurringEditScreen> createState() => _RecurringEditScreenState();
}

class _RecurringEditScreenState extends State<RecurringEditScreen> {
  String _type = 'expense';
  String _frequency = 'monthly';
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  List<Category> _allCategories = [];
  int? _selectedCategoryId;
  DateTime _startDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _type = e.type;
      _frequency = e.frequency;
      _amountController.text = e.amount.toStringAsFixed(2);
      _noteController.text = e.note;
      _selectedCategoryId = e.categoryId;
      _startDate = e.nextRun;
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _amountController.dispose();
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

  Future<void> _pickStartDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _startDate = d);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _toast('Enter a valid amount greater than 0');
      return;
    }
    if (_selectedCategoryId == null) {
      _toast('Pick a category');
      return;
    }
    final template = RecurringTemplate(
      id: widget.editing?.id,
      type: _type,
      amount: amount,
      categoryId: _selectedCategoryId!,
      note: _noteController.text.trim(),
      frequency: _frequency,
      nextRun: DateTime(_startDate.year, _startDate.month, _startDate.day),
    );
    if (widget.editing != null) {
      await DatabaseHelper.instance.updateRecurring(template);
    } else {
      await DatabaseHelper.instance.insertRecurring(template);
    }
    // Immediately create any occurrences already due (e.g. start date today).
    await RecurringService.processDue();
    if (mounted) Navigator.pop(context, true);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
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
    if (confirmed != true) return;
    await DatabaseHelper.instance.deleteRecurring(widget.editing!.id!);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null
            ? 'New Recurring'
            : 'Edit Recurring'),
        actions: [
          if (widget.editing != null)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Expense')),
                ButtonSegment(value: 'income', label: Text('Income')),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _selectedCategoryId = null;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: 'RM ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Category', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _categoryChips(),
            const SizedBox(height: 16),
            const Text('Frequency',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'daily', label: Text('Daily')),
                ButtonSegment(value: 'weekly', label: Text('Weekly')),
                ButtonSegment(value: 'monthly', label: Text('Monthly')),
              ],
              selected: {_frequency},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _frequency = s.first),
            ),
            const SizedBox(height: 16),
            const Text('Starts on / next occurrence',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                    child: Text(
                        DateFormat('EEE, d MMM yyyy').format(_startDate))),
                TextButton.icon(
                  onPressed: _pickStartDate,
                  icon: const Icon(Icons.edit_calendar, size: 18),
                  label: const Text('Pick'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
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
          ],
        ),
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
}
