import 'package:intl/intl.dart';

final NumberFormat _rm =
    NumberFormat.currency(locale: 'en_US', symbol: 'RM ', decimalDigits: 2);

/// Formats a number as Malaysian Ringgit, e.g. 25.5 -> "RM 25.50".
String formatRM(double value) => _rm.format(value);

/// Full date + time, e.g. "Wed, 10 Jun 2026 • 3:45 PM".
String formatDate(DateTime d) =>
    DateFormat('EEE, d MMM yyyy • h:mm a').format(d);
