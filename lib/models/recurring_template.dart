/// A template that auto-generates transactions on a schedule.
///
/// [frequency] is 'daily', 'weekly', or 'monthly'.
/// [nextRun] is the date the next occurrence is due to be created.
class RecurringTemplate {
  final int? id;
  final String type; // 'expense' or 'income'
  final double amount;
  final int categoryId;
  final String note;
  final String frequency;
  final DateTime nextRun;

  RecurringTemplate({
    this.id,
    required this.type,
    required this.amount,
    required this.categoryId,
    this.note = '',
    required this.frequency,
    required this.nextRun,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type,
        'amount': amount,
        'category_id': categoryId,
        'note': note,
        'frequency': frequency,
        'next_run_date': nextRun.millisecondsSinceEpoch,
      };

  factory RecurringTemplate.fromMap(Map<String, Object?> m) => RecurringTemplate(
        id: m['id'] as int?,
        type: m['type'] as String,
        amount: (m['amount'] as num).toDouble(),
        categoryId: m['category_id'] as int,
        note: (m['note'] as String?) ?? '',
        frequency: m['frequency'] as String,
        nextRun: DateTime.fromMillisecondsSinceEpoch(m['next_run_date'] as int),
      );
}
