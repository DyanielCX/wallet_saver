// A small calculator-expression evaluator supporting + - × ÷ with the usual
// operator precedence (× and ÷ before + and −). Used by the amount keypad so
// the user can type e.g. "12.50 × 2" and get 25.00.
//
// evaluateExpression returns the evaluated value, or null if the expression is
// invalid (e.g. divide by zero, malformed input).

bool _isOp(String t) => t == '+' || t == '-' || t == '*' || t == '/';

int _prec(String op) => (op == '*' || op == '/') ? 2 : 1;

List<String> _tokenize(String expr) {
  final tokens = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < expr.length; i++) {
    final ch = expr[i];
    if (ch == ' ') continue;
    if ('0123456789.'.contains(ch)) {
      buf.write(ch);
    } else if ('+-*/'.contains(ch)) {
      if (buf.isNotEmpty) {
        tokens.add(buf.toString());
        buf.clear();
      }
      tokens.add(ch);
    }
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());
  return tokens;
}

/// Shunting-yard: infix tokens -> reverse Polish notation.
List<String> _toRpn(List<String> tokens) {
  final output = <String>[];
  final ops = <String>[];
  for (final t in tokens) {
    if (_isOp(t)) {
      while (ops.isNotEmpty && _isOp(ops.last) && _prec(ops.last) >= _prec(t)) {
        output.add(ops.removeLast());
      }
      ops.add(t);
    } else {
      output.add(t);
    }
  }
  while (ops.isNotEmpty) {
    output.add(ops.removeLast());
  }
  return output;
}

double _evalRpn(List<String> rpn) {
  final stack = <double>[];
  for (final t in rpn) {
    if (_isOp(t)) {
      if (stack.length < 2) throw StateError('malformed expression');
      final b = stack.removeLast();
      final a = stack.removeLast();
      switch (t) {
        case '+':
          stack.add(a + b);
          break;
        case '-':
          stack.add(a - b);
          break;
        case '*':
          stack.add(a * b);
          break;
        case '/':
          if (b == 0) throw StateError('divide by zero');
          stack.add(a / b);
          break;
      }
    } else {
      var num = t;
      if (num.endsWith('.')) num = num.substring(0, num.length - 1);
      if (num.isEmpty || num == '.') num = '0';
      stack.add(double.parse(num));
    }
  }
  if (stack.length != 1) throw StateError('malformed expression');
  return stack.single;
}

double? evaluateExpression(String expr) {
  // Normalize display operators to ASCII math operators.
  final normalized =
      expr.replaceAll('×', '*').replaceAll('÷', '/').replaceAll('−', '-');
  var tokens = _tokenize(normalized);
  // Drop a trailing operator so "12 +" evaluates to 12.
  while (tokens.isNotEmpty && _isOp(tokens.last)) {
    tokens = tokens.sublist(0, tokens.length - 1);
  }
  if (tokens.isEmpty) return 0;
  try {
    final result = _evalRpn(_toRpn(tokens));
    if (result.isNaN || result.isInfinite) return null;
    return result;
  } catch (_) {
    return null;
  }
}
