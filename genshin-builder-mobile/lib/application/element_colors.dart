import 'package:flutter/painting.dart';

import '../domain/game_display.dart';

/// 元素名（小文字の文字列）から [Color] を取得する拡張。
///
/// 使用例:
/// ```dart
/// final color = 'pyro'.elementColor; // Color(0xFFFF6B4A)
/// final fallback = 'unknown'.elementColor; // Color(0xFF9E9E9E)
/// ```
extension ElementColorX on String {
  /// 元素名（小文字正規化済み）に対応する色。
  /// 未知の値の場合はデフォルトグレーを返す（例外は発生しない）。
  Color get elementColor {
    final raw = elementColorMap[toLowerCase()];
    if (raw != null) return Color(raw);
    return const Color(0xFF9E9E9E);
  }
}
