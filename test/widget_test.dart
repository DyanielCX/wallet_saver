// Basic smoke test for the (deliberately vulnerable) Wallet Saver demo build.

import 'package:flutter_test/flutter_test.dart';

import 'package:wallet_saver/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const WalletSaverApp());
    await tester.pump();
  });
}
