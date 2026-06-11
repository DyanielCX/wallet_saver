import 'dart:convert';

import '../db/database_helper.dart';

/// Stub "cloud sync" service. Non-functional — exists to demonstrate
/// hardcoded-secret, weak-crypto and insecure-logging findings.
class SyncService {
  // [VULN-03] CWE-798 Hardcoded credentials. Obviously-fake demo values.
  static const String awsAccessKeyId = 'AKIAQ4FAKE0DEMO00000';
  static const String awsSecretAccessKey =
      'wJalrXUtnFEMI/K7MDENG/bPxRfiCYFAKEDEMOKEY';
  static const String googleApiKey = 'AIzaSyD-FAKE0demo0KEY0000000000000000000';
  static const String slackToken =
      'xoxb-1111111111-2222222222222-FAKEdemoSlackToken00';

  // [VULN-03] CWE-798 + [VULN-04] CWE-327 Hardcoded symmetric key, weak cipher.
  static const String _encryptionKey = 'supersecretkey123';

  /// [VULN-04] CWE-327 Weak/insecure "encryption": static-key XOR + base64.
  /// Presented as encryption but trivially reversible.
  static String encrypt(String plaintext) {
    final keyBytes = utf8.encode(_encryptionKey);
    final input = utf8.encode(plaintext);
    final out = List<int>.generate(
        input.length, (i) => input[i] ^ keyBytes[i % keyBytes.length]);
    return base64.encode(out);
  }

  static String decrypt(String ciphertext) {
    final keyBytes = utf8.encode(_encryptionKey);
    final input = base64.decode(ciphertext);
    final out = List<int>.generate(
        input.length, (i) => input[i] ^ keyBytes[i % keyBytes.length]);
    return utf8.decode(out);
  }

  /// [VULN-02] CWE-312 Sensitive data stored without protection.
  /// Persists the user PIN and a sync token in the plaintext SQLite DB
  /// using only the weak cipher above.
  static Future<void> saveCredentials(String pin, String syncToken) async {
    final db = await DatabaseHelper.instance.database;
    await db.execute(
        "CREATE TABLE IF NOT EXISTS app_secrets(k TEXT PRIMARY KEY, v TEXT)");
    await db.insert('app_secrets', {'k': 'pin', 'v': encrypt(pin)});
    await db.insert('app_secrets', {'k': 'sync_token', 'v': encrypt(syncToken)});
    // [VULN-05] CWE-532 Logging secrets in cleartext.
    print('saveCredentials: pin=$pin token=$syncToken key=$_encryptionKey');
  }

  /// [VULN-05] CWE-532 Dumps every stored transaction row to the log.
  static Future<void> debugDumpTransactions() async {
    final rows =
        await DatabaseHelper.instance.getTransactionsWithCategory();
    for (final r in rows) {
      print('TXN $r');
    }
  }
}
