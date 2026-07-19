import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/config/config_load_log.dart';
import '../../data/config/remote_json_fetch.dart';
import '../../data/db/database_open_exception.dart';
import '../../data/hoyolab/hoyolab_exceptions.dart';
import '../../domain/abyss/abyss_statistics.dart';

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
  if (error is AbyssStatisticsException) {
    return switch (error.failure) {
      AbyssStatisticsFailure.networkError ||
      AbyssStatisticsFailure
          .unknownError => '統計データを取得できませんでした。しばらくしてから再試行してください。',
      AbyssStatisticsFailure.timeout => '統計データの取得がタイムアウトしました。再試行してください。',
      AbyssStatisticsFailure.rateLimited =>
        '統計データの取得が混み合っています。時間をおいて再試行してください。',
      AbyssStatisticsFailure.invalidResponse =>
        '統計データの形式を確認できませんでした。しばらくしてから再試行してください。',
      AbyssStatisticsFailure.notConfigured => '統計機能の接続先が設定されていません。',
      AbyssStatisticsFailure.featureDisabled => '深境螺旋統計は現在利用できません。',
      AbyssStatisticsFailure.noData => '表示できる統計データがありません。',
      AbyssStatisticsFailure.staleCache => '前回取得した統計データを表示しています。',
    };
  }
  if (error is TimeoutException) {
    return '通信がタイムアウトしました。再試行してください。';
  }
  if (error is RemoteJsonFetchException || error is ConfigLoadException) {
    return '設定データの読み込みに失敗しました。しばらくしてから再試行してください。';
  }
  if (error is FormatException) {
    return 'データの形式が不正です。再同期するか、しばらくしてから再試行してください。';
  }
  if (error is DatabaseOpenException) {
    return switch (error.kind) {
      DatabaseFailureKind.downgrade =>
        'このデータは新しいアプリ版で作成されています。新しいバージョンへ戻してください。',
      DatabaseFailureKind.locked => 'データベースは使用中です。少し待ってから再試行してください。',
      DatabaseFailureKind.readOnly ||
      DatabaseFailureKind.diskFull => '端末の保存領域を確認してから再試行してください。',
      DatabaseFailureKind.corrupt => 'データベースを読み取れませんでした。初期化せず、サポートへお問い合わせください。',
      DatabaseFailureKind.migration ||
      DatabaseFailureKind.io ||
      DatabaseFailureKind.unknown => 'データベースを開けませんでした。データは初期化せず保持されています。',
    };
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
