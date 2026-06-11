import 'package:flutter/material.dart';

/// The on-screen calculator pad used for amount entry (replaces the system
/// keyboard). It is "dumb": it just reports each key press via [onKey]; the
/// parent screen owns the expression state and evaluation.
class CalculatorKeypad extends StatelessWidget {
  final ValueChanged<String> onKey;
  final Color accent;

  const CalculatorKeypad({super.key, required this.onKey, required this.accent});

  static const List<List<String>> _rows = [
    ['7', '8', '9', '÷'],
    ['4', '5', '6', '×'],
    ['1', '2', '3', '−'],
    ['.', '0', '⌫', '+'],
  ];

  bool _isOp(String s) => '+−×÷'.contains(s);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          SizedBox(
            height: 58,
            child: Row(
              children: [for (final key in row) Expanded(child: _button(key))],
            ),
          ),
        SizedBox(
          height: 58,
          child: Row(
            children: [
              Expanded(child: _button('C')),
              Expanded(flex: 3, child: _button('=', filled: true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _button(String key, {bool filled = false}) {
    Color bg = Colors.white;
    Color fg = Colors.black87;
    if (filled) {
      bg = accent;
      fg = Colors.white;
    } else if (_isOp(key)) {
      fg = accent;
    } else if (key == 'C' || key == '⌫') {
      fg = Colors.red.shade400;
    }
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onKey(key),
          child: Center(
            child: Text(
              key,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
