import '../db/database_helper.dart';
import '../models/app_transaction.dart';

/// Creates any due recurring transactions. Called on app launch ("catch-up"):
/// for each template, it inserts an occurrence for every scheduled date that
/// has passed (each dated correctly), then advances the template's next-run
/// date into the future.
class RecurringService {
  /// Returns the number of transactions created.
  static Future<int> processDue() async {
    final db = DatabaseHelper.instance;
    final templates = await db.getRecurringTemplates();
    final now = DateTime.now();
    var created = 0;

    for (final t in templates) {
      var next = t.nextRun;
      // Safety cap to avoid pathological loops (e.g. a daily template whose
      // start date is years in the past).
      var guard = 0;
      while (!next.isAfter(now) && guard < 1000) {
        await db.insertTransaction(AppTransaction(
          type: t.type,
          amount: t.amount,
          categoryId: t.categoryId,
          date: next,
          note: t.note,
        ));
        created++;
        next = _advance(next, t.frequency);
        guard++;
      }
      if (next != t.nextRun) {
        await db.setRecurringNextRun(t.id!, next);
      }
    }
    return created;
  }

  static DateTime _advance(DateTime d, String frequency) {
    switch (frequency) {
      case 'weekly':
        return d.add(const Duration(days: 7));
      case 'monthly':
        var y = d.year;
        var m = d.month + 1;
        if (m > 12) {
          m = 1;
          y++;
        }
        final lastDay = DateTime(y, m + 1, 0).day; // last day of month m
        final day = d.day <= lastDay ? d.day : lastDay;
        return DateTime(y, m, day, d.hour, d.minute);
      case 'daily':
      default:
        return d.add(const Duration(days: 1));
    }
  }
}
