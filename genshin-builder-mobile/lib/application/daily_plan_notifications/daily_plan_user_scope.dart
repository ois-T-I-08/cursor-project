import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Non-reversible short scope for WorkManager unique names (never log raw userId).
String dailyPlanSafeUserScope(String userId) {
  final digest = sha256.convert(utf8.encode(userId));
  return digest.toString().substring(0, 12);
}
