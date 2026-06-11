import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_transaction.dart';
import '../models/category.dart';
import '../models/recurring_template.dart';

/// Single access point to the local SQLite database.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'wallet_saver.db');
    return openDatabase(path,
        version: 3, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  static const _createBudgetsTable = '''
    CREATE TABLE budgets(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category_id INTEGER NOT NULL,
      scope TEXT NOT NULL,
      year INTEGER,
      month INTEGER,
      limit_amount REAL NOT NULL,
      FOREIGN KEY (category_id) REFERENCES categories(id)
    )
  ''';

  static const _createRecurringTable = '''
    CREATE TABLE recurring_templates(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      amount REAL NOT NULL,
      category_id INTEGER NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      frequency TEXT NOT NULL,
      next_run_date INTEGER NOT NULL,
      FOREIGN KEY (category_id) REFERENCES categories(id)
    )
  ''';

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(_createBudgetsTable);
    }
    if (oldVersion < 3) {
      await db.execute(_createRecurringTable);
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        icon TEXT NOT NULL DEFAULT '',
        is_custom INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        category_id INTEGER NOT NULL,
        date INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (category_id) REFERENCES categories(id)
      )
    ''');
    await db.execute(_createBudgetsTable);
    await db.execute(_createRecurringTable);
    await _seedCategories(db);
  }

  /// Seeds the default category list (per the PRD). All editable/removable later.
  Future<void> _seedCategories(Database db) async {
    const defaults = [
      {'name': 'Food', 'type': 'expense', 'icon': '🍔'},
      {'name': 'Transport', 'type': 'expense', 'icon': '🚗'},
      {'name': 'Groceries', 'type': 'expense', 'icon': '🛒'},
      {'name': 'Mobile Bill', 'type': 'expense', 'icon': '📱'},
      {'name': 'Utilities', 'type': 'expense', 'icon': '💡'},
      {'name': 'Shopping', 'type': 'expense', 'icon': '🛍️'},
      {'name': 'Entertainment', 'type': 'expense', 'icon': '🎮'},
      {'name': 'Others', 'type': 'expense', 'icon': '📦'},
      {'name': 'Salary', 'type': 'income', 'icon': '💰'},
      {'name': 'Other Income', 'type': 'income', 'icon': '➕'},
    ];
    final batch = db.batch();
    for (final c in defaults) {
      batch.insert('categories', {...c, 'is_custom': 0});
    }
    await batch.commit(noResult: true);
  }

  // ---- Categories ----

  Future<List<Category>> getCategories({String? type}) async {
    final db = await database;
    final rows = type == null
        ? await db.query('categories', orderBy: 'id')
        : await db.query('categories',
            where: 'type = ?', whereArgs: [type], orderBy: 'id');
    return rows.map(Category.fromMap).toList();
  }

  Future<int> insertCategory(Category c) async {
    final db = await database;
    final map = c.toMap()..remove('id');
    return db.insert('categories', map);
  }

  Future<int> updateCategory(Category c) async {
    final db = await database;
    final map = c.toMap()..remove('id');
    return db.update('categories', map, where: 'id = ?', whereArgs: [c.id]);
  }

  /// Number of transactions + recurring templates that use this category.
  /// Used to block deleting a category that's still in use.
  Future<int> getCategoryUsageCount(int categoryId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        (SELECT COUNT(*) FROM transactions WHERE category_id = ?) +
        (SELECT COUNT(*) FROM recurring_templates WHERE category_id = ?) AS cnt
    ''', [categoryId, categoryId]);
    return (rows.first['cnt'] as num).toInt();
  }

  /// Deletes a category (and any budgets attached to it). Caller must ensure
  /// the category is not in use by transactions/recurring templates.
  Future<void> deleteCategory(int categoryId) async {
    final db = await database;
    await db.delete('budgets',
        where: 'category_id = ?', whereArgs: [categoryId]);
    await db.delete('categories', where: 'id = ?', whereArgs: [categoryId]);
  }

  // ---- Transactions ----

  Future<int> insertTransaction(AppTransaction t) async {
    final db = await database;
    final map = t.toMap()..remove('id');
    return db.insert('transactions', map);
  }

  /// Transactions joined with their category name/icon, newest first.
  Future<List<Map<String, Object?>>> getTransactionsWithCategory() async {
    final db = await database;
    return db.rawQuery('''
      SELECT t.*, c.name AS category_name, c.icon AS category_icon
      FROM transactions t
      JOIN categories c ON c.id = t.category_id
      ORDER BY t.date DESC, t.id DESC
    ''');
  }

  /// All-time totals across every transaction: (income, expense).
  Future<(double, double)> getAllTimeTotals() async {
    final db = await database;
    final rows = await db
        .rawQuery('SELECT type, SUM(amount) AS total FROM transactions GROUP BY type');
    double income = 0;
    double expense = 0;
    for (final r in rows) {
      final total = (r['total'] as num?)?.toDouble() ?? 0;
      if (r['type'] == 'income') {
        income = total;
      } else if (r['type'] == 'expense') {
        expense = total;
      }
    }
    return (income, expense);
  }

  /// Distinct months (first-of-month dates) that have transactions, newest first.
  Future<List<DateTime>> getTransactionMonths() async {
    final db = await database;
    final rows = await db.query('transactions', columns: ['date']);
    final months = <String, DateTime>{};
    for (final r in rows) {
      final d = DateTime.fromMillisecondsSinceEpoch(r['date'] as int);
      months['${d.year}-${d.month}'] = DateTime(d.year, d.month);
    }
    final list = months.values.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// Transactions within [start, end) joined with category, newest first.
  Future<List<Map<String, Object?>>> getTransactionsWithCategoryBetween(
      DateTime start, DateTime end) async {
    final db = await database;
    return db.rawQuery('''
      SELECT t.*, c.name AS category_name, c.icon AS category_icon
      FROM transactions t
      JOIN categories c ON c.id = t.category_id
      WHERE t.date >= ? AND t.date < ?
      ORDER BY t.date DESC, t.id DESC
    ''', [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch]);
  }

  Future<int> updateTransaction(AppTransaction t) async {
    final db = await database;
    final map = t.toMap()..remove('id');
    return db.update('transactions', map, where: 'id = ?', whereArgs: [t.id]);
  }

  Future<void> deleteTransaction(int id) async {
    final db = await database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Budgets ----

  /// Recurring default limits: category_id -> limit.
  Future<Map<int, double>> getDefaultBudgets() async {
    final db = await database;
    final rows = await db.query('budgets', where: "scope = 'default'");
    return {
      for (final r in rows)
        r['category_id'] as int: (r['limit_amount'] as num).toDouble()
    };
  }

  /// Month-specific override limits for the given month: category_id -> limit.
  Future<Map<int, double>> getMonthBudgets(int year, int month) async {
    final db = await database;
    final rows = await db.query('budgets',
        where: "scope = 'month' AND year = ? AND month = ?",
        whereArgs: [year, month]);
    return {
      for (final r in rows)
        r['category_id'] as int: (r['limit_amount'] as num).toDouble()
    };
  }

  /// Effective limit for a category in a month: override if set, else default.
  Future<double?> effectiveLimit(int categoryId, int year, int month) async {
    final overrides = await getMonthBudgets(year, month);
    if (overrides.containsKey(categoryId)) return overrides[categoryId];
    final defaults = await getDefaultBudgets();
    return defaults[categoryId];
  }

  Future<void> setDefaultBudget(int categoryId, double limit) async {
    final db = await database;
    await db.delete('budgets',
        where: "category_id = ? AND scope = 'default'", whereArgs: [categoryId]);
    await db.insert('budgets', {
      'category_id': categoryId,
      'scope': 'default',
      'year': null,
      'month': null,
      'limit_amount': limit,
    });
  }

  Future<void> removeDefaultBudget(int categoryId) async {
    final db = await database;
    await db.delete('budgets',
        where: "category_id = ? AND scope = 'default'", whereArgs: [categoryId]);
  }

  Future<void> setMonthBudget(
      int categoryId, int year, int month, double limit) async {
    final db = await database;
    await db.delete('budgets',
        where: "category_id = ? AND scope = 'month' AND year = ? AND month = ?",
        whereArgs: [categoryId, year, month]);
    await db.insert('budgets', {
      'category_id': categoryId,
      'scope': 'month',
      'year': year,
      'month': month,
      'limit_amount': limit,
    });
  }

  Future<void> removeMonthBudget(int categoryId, int year, int month) async {
    final db = await database;
    await db.delete('budgets',
        where: "category_id = ? AND scope = 'month' AND year = ? AND month = ?",
        whereArgs: [categoryId, year, month]);
  }

  /// Expense spending per category in a month: category_id -> total.
  Future<Map<int, double>> getMonthSpendingByCategory(
      int year, int month) async {
    final db = await database;
    final start = DateTime(year, month, 1).millisecondsSinceEpoch;
    final end = DateTime(year, month + 1, 1).millisecondsSinceEpoch;
    final rows = await db.rawQuery('''
      SELECT category_id, SUM(amount) AS total
      FROM transactions
      WHERE type = 'expense' AND date >= ? AND date < ?
      GROUP BY category_id
    ''', [start, end]);
    return {
      for (final r in rows)
        r['category_id'] as int: (r['total'] as num).toDouble()
    };
  }

  /// Total expense for one category in a month.
  Future<double> getCategoryMonthSpending(
      int categoryId, int year, int month) async {
    final db = await database;
    final start = DateTime(year, month, 1).millisecondsSinceEpoch;
    final end = DateTime(year, month + 1, 1).millisecondsSinceEpoch;
    final rows = await db.rawQuery('''
      SELECT SUM(amount) AS total FROM transactions
      WHERE type = 'expense' AND category_id = ? AND date >= ? AND date < ?
    ''', [categoryId, start, end]);
    final total = rows.first['total'];
    return total == null ? 0.0 : (total as num).toDouble();
  }

  // ---- Recurring templates ----

  Future<List<RecurringTemplate>> getRecurringTemplates() async {
    final db = await database;
    final rows =
        await db.query('recurring_templates', orderBy: 'next_run_date');
    return rows.map(RecurringTemplate.fromMap).toList();
  }

  Future<int> insertRecurring(RecurringTemplate t) async {
    final db = await database;
    final map = t.toMap()..remove('id');
    return db.insert('recurring_templates', map);
  }

  Future<int> updateRecurring(RecurringTemplate t) async {
    final db = await database;
    final map = t.toMap()..remove('id');
    return db.update('recurring_templates', map,
        where: 'id = ?', whereArgs: [t.id]);
  }

  Future<void> deleteRecurring(int id) async {
    final db = await database;
    await db.delete('recurring_templates', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setRecurringNextRun(int id, DateTime nextRun) async {
    final db = await database;
    await db.update(
        'recurring_templates', {'next_run_date': nextRun.millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }

  // [VULN-01] CWE-89 SQL Injection.
  // User-supplied search text is concatenated directly into the SQL string
  // instead of being passed via whereArgs. A note like  x' OR '1'='1
  // returns every row; ');DROP TABLE transactions;-- can corrupt the schema.
  Future<List<Map<String, Object?>>> searchTransactions(String query) async {
    final db = await database;
    final sql =
        "SELECT t.*, c.name AS category_name, c.icon AS category_icon "
        "FROM transactions t JOIN categories c ON c.id = t.category_id "
        "WHERE t.note LIKE '%$query%' OR c.name LIKE '%$query%' "
        "ORDER BY t.date DESC";
    // [VULN-05] CWE-532 Sensitive data written to logs.
    print('searchTransactions SQL => $sql');
    return db.rawQuery(sql);
  }

  // [VULN-01] CWE-89 SQL Injection via category filter.
  // Raw value interpolated into the WHERE clause.
  Future<List<Map<String, Object?>>> transactionsByCategoryName(
      String categoryName) async {
    final db = await database;
    return db.rawQuery(
        "SELECT t.* FROM transactions t JOIN categories c ON c.id = t.category_id "
        "WHERE c.name = '$categoryName'");
  }
}
