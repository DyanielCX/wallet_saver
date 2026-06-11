import 'package:flutter/material.dart';

/// Primary brand color — green (growth / money), per the PRD.
const seedGreen = Color(0xFF2E7D32);

/// Semantic colors used across the app.
const expenseColor = Color(0xFFD32F2F); // red for money going out
const incomeColor = Color(0xFF2E7D32); // green for money coming in

/// Distinct colors for chart categories (cycled if there are more categories).
const chartPalette = <Color>[
  Color(0xFF2E7D32),
  Color(0xFF1565C0),
  Color(0xFFEF6C00),
  Color(0xFF6A1B9A),
  Color(0xFFC62828),
  Color(0xFF00838F),
  Color(0xFFAD1457),
  Color(0xFF558B2F),
  Color(0xFF4527A0),
  Color(0xFFF9A825),
  Color(0xFF00695C),
  Color(0xFF5D4037),
];

Color chartColor(int index) => chartPalette[index % chartPalette.length];

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedGreen,
    brightness: Brightness.light,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF6F8F6),
    appBarTheme: const AppBarTheme(
      backgroundColor: seedGreen,
      foregroundColor: Colors.white,
    ),
  );
}
