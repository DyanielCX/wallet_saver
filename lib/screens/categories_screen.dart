import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/category.dart';
import '../theme.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Category> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cats = await DatabaseHelper.instance.getCategories();
    setState(() {
      _categories = cats;
      _loading = false;
    });
  }

  List<Category> _of(String type) =>
      _categories.where((c) => c.type == type).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editCategory(),
        backgroundColor: seedGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                _header('Expense'),
                ..._of('expense').map(_tile),
                _header('Income'),
                ..._of('income').map(_tile),
              ],
            ),
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
      );

  Widget _tile(Category c) => ListTile(
        leading: Text(c.icon, style: const TextStyle(fontSize: 22)),
        title: Text(c.name),
        trailing: const Icon(Icons.edit, size: 18),
        onTap: () => _editCategory(c),
      );

  Future<void> _editCategory([Category? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final iconCtrl = TextEditingController(text: existing?.icon ?? '');
    var type = existing?.type ?? 'expense';
    final isNew = existing == null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
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
              Text(isNew ? 'New Category' : 'Edit Category',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: iconCtrl,
                      textAlign: TextAlign.center,
                      maxLength: 2,
                      style: const TextStyle(fontSize: 22),
                      decoration: const InputDecoration(
                        labelText: 'Icon',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (isNew)
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'expense', label: Text('Expense')),
                    ButtonSegment(value: 'income', label: Text('Income')),
                  ],
                  selected: {type},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setSheet(() => type = s.first),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Type: ${type[0].toUpperCase()}${type.substring(1)}',
                      style: TextStyle(color: Colors.grey.shade600)),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Enter a name')));
                    return;
                  }
                  final icon =
                      iconCtrl.text.trim().isEmpty ? '🏷️' : iconCtrl.text.trim();
                  final category = Category(
                    id: existing?.id,
                    name: name,
                    type: type,
                    icon: icon,
                    isCustom: existing?.isCustom ?? true,
                  );
                  if (isNew) {
                    await DatabaseHelper.instance.insertCategory(category);
                  } else {
                    await DatabaseHelper.instance.updateCategory(category);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
              if (!isNew)
                TextButton.icon(
                  onPressed: () => _confirmDelete(ctx, existing),
                  icon: const Icon(Icons.delete_outline, color: expenseColor),
                  label: const Text('Delete',
                      style: TextStyle(color: expenseColor)),
                ),
            ],
          ),
        ),
      ),
    );
    await _load();
  }

  Future<void> _confirmDelete(BuildContext sheetCtx, Category c) async {
    final usage = await DatabaseHelper.instance.getCategoryUsageCount(c.id!);
    if (!sheetCtx.mounted) return;
    if (usage > 0) {
      await showDialog<void>(
        context: sheetCtx,
        builder: (_) => AlertDialog(
          title: const Text('Cannot delete'),
          content: Text(
              '"${c.name}" is used by $usage transaction(s) or recurring item(s). '
              'Reassign or delete those first, or just rename this category instead.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(sheetCtx),
                child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: sheetCtx,
      builder: (_) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('"${c.name}" will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(sheetCtx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(sheetCtx, true),
            child: const Text('Delete', style: TextStyle(color: expenseColor)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DatabaseHelper.instance.deleteCategory(c.id!);
    if (sheetCtx.mounted) Navigator.pop(sheetCtx); // close the edit sheet
  }
}
