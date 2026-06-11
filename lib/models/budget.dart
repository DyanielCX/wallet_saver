/// A budget limit for a category.
///
/// [scope] is either:
///   - 'default' : a recurring monthly limit that applies to every month
///                 (year/month are null).
///   - 'month'   : an override for one specific month (year + month set).
///
/// The effective limit for a given month is the 'month' override if present,
/// otherwise the 'default'.
class Budget {
  final int? id;
  final int categoryId;
  final String scope;
  final int? year;
  final int? month;
  final double limit;

  Budget({
    this.id,
    required this.categoryId,
    required this.scope,
    this.year,
    this.month,
    required this.limit,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'category_id': categoryId,
        'scope': scope,
        'year': year,
        'month': month,
        'limit_amount': limit,
      };

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
        id: m['id'] as int?,
        categoryId: m['category_id'] as int,
        scope: m['scope'] as String,
        year: m['year'] as int?,
        month: m['month'] as int?,
        limit: (m['limit_amount'] as num).toDouble(),
      );
}
