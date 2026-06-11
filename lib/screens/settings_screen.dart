import 'package:flutter/material.dart';

import '../services/csv_service.dart';
import 'categories_screen.dart';
import 'recurring_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Manage Categories'),
            subtitle: const Text('Add, edit or remove categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CategoriesScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.event_repeat),
            title: const Text('Recurring Transactions'),
            subtitle: const Text('Auto-log rent, salary, subscriptions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RecurringScreen()),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Data (CSV)',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Export to CSV'),
            subtitle: const Text('Save all transactions to a file'),
            onTap: () => _export(context),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Import from CSV'),
            subtitle: const Text('Add transactions from a file'),
            onTap: () => _import(context),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    try {
      final path = await CsvService.exportTransactions();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(path == null
            ? 'Export cancelled'
            : 'Exported successfully'),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _import(BuildContext context) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import from CSV?'),
        content: const Text(
            'This ADDS the transactions from the file to your existing data '
            '(it does not replace them). Categories that don\'t exist yet will '
            'be created automatically.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue')),
        ],
      ),
    );
    if (proceed != true) return;

    try {
      final result = await CsvService.importTransactions();
      if (!context.mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Import cancelled')));
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Import complete'),
          content: Text('Imported: ${result.imported}\n'
              'Duplicates skipped: ${result.duplicates}\n'
              'Invalid rows skipped: ${result.skipped}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}
