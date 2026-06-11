/// A spending/income category, e.g. "Food" (expense) or "Salary" (income).
class Category {
  final int? id;
  final String name;
  final String type; // 'expense' or 'income'
  final String icon; // an emoji, e.g. '🍔'
  final bool isCustom; // true if the user created it (vs. a seeded default)

  Category({
    this.id,
    required this.name,
    required this.type,
    this.icon = '',
    this.isCustom = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'icon': icon,
        'is_custom': isCustom ? 1 : 0,
      };

  factory Category.fromMap(Map<String, Object?> m) => Category(
        id: m['id'] as int?,
        name: m['name'] as String,
        type: m['type'] as String,
        icon: (m['icon'] as String?) ?? '',
        isCustom: (m['is_custom'] as int? ?? 0) == 1,
      );
}
