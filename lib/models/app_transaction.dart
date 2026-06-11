/// A single recorded transaction (an expense or an income entry).
/// Named `AppTransaction` to avoid clashing with sqflite's `Transaction`.
class AppTransaction {
  final int? id;
  final String type; // 'expense' or 'income'
  final double amount; // always positive; `type` carries the direction
  final int categoryId;
  final DateTime date;
  final String note;

  AppTransaction({
    this.id,
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.note = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type,
        'amount': amount,
        'category_id': categoryId,
        'date': date.millisecondsSinceEpoch,
        'note': note,
      };

  factory AppTransaction.fromMap(Map<String, Object?> m) => AppTransaction(
        id: m['id'] as int?,
        type: m['type'] as String,
        amount: (m['amount'] as num).toDouble(),
        categoryId: m['category_id'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        note: (m['note'] as String?) ?? '',
      );
}
