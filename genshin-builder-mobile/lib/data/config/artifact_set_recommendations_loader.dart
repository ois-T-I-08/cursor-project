import 'dart:convert';

import 'package:flutter/services.dart';

/// 設定 JSON の推奨 + エイリアス。
class ArtifactSetRecommendationsConfig {
  const ArtifactSetRecommendationsConfig({
    required this.recommendations,
    required this.aliases,
  });

  /// セット名（JP またはエイリアスキー）→ キャラ名 or ID
  final Map<String, List<String>> recommendations;

  /// 別名 → 正規セット名（Amber JP 名）
  final Map<String, String> aliases;
}

/// `artifact_set_recommendations.json` の読み込み。
class ArtifactSetRecommendationsLoader {
  const ArtifactSetRecommendationsLoader({
    this.assetPath = 'assets/config/artifact_set_recommendations.json',
  });

  final String assetPath;

  Future<ArtifactSetRecommendationsConfig> load() async {
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final map = json['recommendations'] as Map<String, dynamic>? ?? {};
    final aliasRaw = json['aliases'] as Map<String, dynamic>? ?? {};
    return ArtifactSetRecommendationsConfig(
      recommendations: {
        for (final e in map.entries)
          e.key: (e.value as List<dynamic>)
              .map((x) => x.toString())
              .toList(growable: false),
      },
      aliases: {for (final e in aliasRaw.entries) e.key: e.value.toString()},
    );
  }
}
