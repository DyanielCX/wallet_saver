import 'package:flutter/material.dart';

import 'screens/main_scaffold.dart';
import 'services/notification_service.dart';
import 'services/recurring_service.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.init();
  // Catch-up: create any recurring transactions that have come due.
  await RecurringService.processDue();
  runApp(const WalletSaverApp());
}

class WalletSaverApp extends StatelessWidget {
  const WalletSaverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wallet Saver',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const MainScaffold(),
    );
  }
}
