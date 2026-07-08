/// DB エントリポイント。
///
/// 現状は sqflite 実装（`sqflite_database.dart`）。
/// Drift 移行（P1-0）完了時に `drift/app_database.dart` へ差し替える。
library;

export 'sqflite_database.dart';
