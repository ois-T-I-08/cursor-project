import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/hoyolab/hoyolab_exceptions.dart';

/// ユーザー向けに安全なエラー文言へ変換する。
/// 内部例外・スタック・URL・パスは露出させない。
String userFacingError(
  Object? error, {
  String fallback = '読み込みに失敗しました。しばらくしてから再試行してください。',
}) {
  if (error == null) return fallback;
  if (error is String) {
    final trimmed = error.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }
  if (error is HoyolabApiException) return error.userMessage;
  if (error is TimeoutException) {
    return '通信がタイムアウトしました。再試行してください。';
  }
  if (error is FormatException) {
    return 'データの形式が不正です。再同期するか、しばらくしてから再試行してください。';
  }
  return fallback;
}

/// 同期など複数エラーをまとめるときのユーザー向け文言。
String userFacingSyncErrors(Iterable<String> errors) {
  final count = errors.length;
  if (count == 0) return '同期に失敗しました。再試行してください。';
  return '一部のデータの同期に失敗しました（$count件）。再試行してください。';
}

/// 開発者向けログ（リリースでは出力しない）。
void logAppError(Object error, [StackTrace? stack, String? context]) {
  if (!kDebugMode) return;
  final prefix = context == null ? 'AppError' : 'AppError($context)';
  debugPrint('$prefix: $error');
  if (stack != null) debugPrint('$stack');
}
