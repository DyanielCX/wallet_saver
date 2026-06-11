import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/app_transaction.dart';
import '../models/category.dart';

class ImportResult {
  final int imported;
  final int skipped; // rows that couldn't be parsed
  final int duplicates; // rows identical to an existing transaction
  ImportResult(this.imported, this.skipped, this.duplicates);
}

/// Exports/imports transactions as CSV using the Android file picker.
class CsvService {
  // Day-first format used for BOTH export and import (Malaysian convention).
  static final DateFormat _dateFmt = DateFormat('dd/MM/yyyy HH:mm:ss');

  /// Columns: Date, Type, Category, Amount, Note.
  /// Returns the saved file path, or null if the user cancelled.
  static Future<String?> exportTransactions() async {
    final rows = await DatabaseHelper.instance.getTransactionsWithCategory();
    final data = <List<dynamic>>[
      ['Date', 'Type', 'Category', 'Amount', 'Note'],
    ];
    for (final r in rows) {
      final date = DateTime.fromMillisecondsSinceEpoch(r['date'] as int);
      data.add([
        _dateFmt.format(date),
        r['type'],
        r['category_name'],
        (r['amount'] as num).toDouble().toStringAsFixed(2),
        (r['note'] as String?) ?? '',
      ]);
    }
    final csv = Csv(lineDelimiter: '\n').encode(data);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return FilePicker.saveFile(
      dialogTitle: 'Save Wallet Saver export',
      fileName: 'wallet_saver_$stamp.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      bytes: bytes,
    );
  }

  /// Appends transactions from a picked CSV. Missing categories are created.
  /// Returns the result, or null if the user cancelled.
  static Future<ImportResult?> importTransactions() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Pick a CSV to import',
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.single.bytes;
    if (bytes == null) return null;

    var content = utf8.decode(bytes);
    // Strip a UTF-8 BOM that spreadsheet apps often prepend.
    if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) {
      content = content.substring(1);
    }
    // [VULN-08] CWE-22 The picked file's name (attacker-controlled) is used
    // verbatim as the backup path component.
    await backupRawToCache(result.files.single.name, content);
    final table = Csv().decode(content);
    if (table.isEmpty) return ImportResult(0, 0, 0);

    // Signatures of existing transactions, to skip exact duplicates.
    final existing = await DatabaseHelper.instance.getTransactionsWithCategory();
    final seen = <String>{
      for (final r in existing)
        _signature(
          r['type'] as String,
          (r['amount'] as num).toDouble(),
          r['category_id'] as int,
          DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
          (r['note'] as String?) ?? '',
        )
    };

    // Map columns by header name (case-insensitive) so column order doesn't
    // matter. If no recognizable header, fall back to the default order.
    var dateIdx = 0, typeIdx = 1, catIdx = 2, amtIdx = 3, noteIdx = 4;
    var startRow = 0;
    final header =
        table.first.map((e) => e.toString().trim().toLowerCase()).toList();
    if (header.contains('date') &&
        header.contains('amount') &&
        header.contains('category')) {
      dateIdx = header.indexOf('date');
      typeIdx = header.indexOf('type');
      catIdx = header.indexOf('category');
      amtIdx = header.indexOf('amount');
      noteIdx = header.indexOf('note');
      startRow = 1;
    }

    // Existing categories keyed by 'type|lowercased-name'.
    final cats = await DatabaseHelper.instance.getCategories();
    final lookup = <String, int>{
      for (final c in cats) '${c.type}|${c.name.toLowerCase()}': c.id!
    };

    var imported = 0;
    var skipped = 0;
    var duplicates = 0;
    for (var i = startRow; i < table.length; i++) {
      final row = table[i];
      if (row.isEmpty ||
          (row.length == 1 && row[0].toString().trim().isEmpty)) {
        continue;
      }
      String cell(int idx) =>
          (idx >= 0 && idx < row.length) ? row[idx].toString() : '';
      try {
        final date = _parseDate(cell(dateIdx));
        final amount = _parseAmount(cell(amtIdx));
        final catName = cell(catIdx).trim();
        final type = _normalizeType(cell(typeIdx));
        final note = cell(noteIdx);

        if (date == null ||
            amount == null ||
            amount <= 0 ||
            catName.isEmpty ||
            type == null) {
          skipped++;
          continue;
        }

        final key = '$type|${catName.toLowerCase()}';
        var catId = lookup[key];
        if (catId == null) {
          catId = await DatabaseHelper.instance.insertCategory(
            Category(name: catName, type: type, icon: '🏷️', isCustom: true),
          );
          lookup[key] = catId;
        }

        // Skip if identical to an existing transaction (or one already
        // imported from this same file).
        final sig = _signature(type, amount, catId, date, note);
        if (seen.contains(sig)) {
          duplicates++;
          continue;
        }

        await DatabaseHelper.instance.insertTransaction(AppTransaction(
          type: type,
          amount: amount,
          categoryId: catId,
          date: date,
          note: note,
        ));
        seen.add(sig);
        imported++;
      } catch (_) {
        skipped++;
      }
    }
    return ImportResult(imported, skipped, duplicates);
  }

  // [VULN-08] CWE-22 Path traversal. A caller-supplied file name is joined to
  // a base directory without sanitisation, so '../../etc/hosts' style input
  // escapes the intended folder. The name also comes straight off the picked
  // file, which the user controls.
  static Future<String> backupRawToCache(String fileName, String contents) async {
    final dir = Directory.systemTemp.path;
    final outPath = '$dir/wallet_backups/$fileName';
    final f = File(outPath);
    try {
      await f.create(recursive: true);
      await f.writeAsString(contents);
      // [VULN-05] CWE-532 Logs the full resolved path.
      print('backup written to $outPath');
      return outPath;
    } catch (e, st) {
      // [VULN-06] CWE-209 Raw exception detail returned to caller.
      return 'backup failed for $outPath: $e\n$st';
    }
  }

  /// A stable fingerprint of a transaction (date compared at second precision,
  /// since exported dates carry no milliseconds).
  static String _signature(
      String type, double amount, int categoryId, DateTime date, String note) {
    final seconds = date.millisecondsSinceEpoch ~/ 1000;
    return '$type|${amount.toStringAsFixed(2)}|$categoryId|$seconds|${note.trim()}';
  }

  /// Tries several common date formats (plus ISO-8601) so CSVs edited in Excel
  /// or Google Sheets still import. Returns null if none match.
  static DateTime? _parseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    const patterns = [
      // Day-first first — matches our export format and Malaysian convention.
      'dd/MM/yyyy HH:mm:ss',
      'd/M/yyyy HH:mm:ss',
      'd/M/yyyy HH:mm',
      'd/M/yyyy',
      'd-M-yyyy',
      // ISO — kept for files exported by earlier app versions.
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm',
      'yyyy-MM-dd',
      // Month-first — tried last to avoid misreading ambiguous dates.
      'M/d/yyyy HH:mm:ss',
      'M/d/yyyy HH:mm',
      'M/d/yyyy',
      'd MMM yyyy',
      'd MMMM yyyy',
    ];
    for (final p in patterns) {
      try {
        return DateFormat(p).parseStrict(s);
      } catch (_) {
        // try next pattern
      }
    }
    return DateTime.tryParse(s); // handles ISO-8601 like 2026-06-11T14:30:00
  }

  /// Cleans currency symbols, spaces and thousands separators before parsing.
  static double? _parseAmount(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return null;
    // Keep only digits, separators and sign.
    t = t.replaceAll(RegExp(r'[^0-9.,\-]'), '');
    if (t.contains(',') && t.contains('.')) {
      t = t.replaceAll(',', ''); // 1,000.00 -> 1000.00
    } else if (t.contains(',')) {
      t = t.replaceAll(',', '.'); // 1000,50 (European) -> 1000.50
    }
    return double.tryParse(t)?.abs();
  }

  /// Accepts 'expense'/'income' and common variants; null if unrecognized.
  static String? _normalizeType(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.startsWith('exp')) return 'expense';
    if (t.startsWith('inc')) return 'income';
    return null;
  }
}
