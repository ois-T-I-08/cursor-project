import 'dart:convert';
import 'dart:io';

import 'package:genshin_builder_mobile/data/artifact_score/artifact_score_weight.dart';
import 'package:genshin_builder_mobile/domain/artifact_score.dart';

/// 全キャラの取得基準を検証するツール。
/// 期待値: inferScoreType + artifact_score_type_overrides.json + 重みJSON
void main() async {
  final nameOverrides = await _loadNameOverridesFromJson();
  final weightProfiles = await _loadWeightProfilesFromJson();

  final client = HttpClient();
  final req = await client.getUrl(
    Uri.parse('https://gi.yatta.moe/api/v2/jp/avatar'),
  );
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  final json = jsonDecode(body) as Map<String, dynamic>;
  final items = (json['data'] as Map)['items'] as Map<String, dynamic>;

  final currentWrong = <String>[];
  final byType = <String, int>{};

  for (final raw in items.values) {
    final a = raw as Map<String, dynamic>;
    final name = a['name'] as String?;
    final elementKey = a['element'] as String?;
    if (name == null || elementKey == null) continue;
    final id = '${a['id']}';
    if (id.startsWith('10000007-')) continue;

    final isTraveler = id.startsWith('10000005-');
    final displayName = isTraveler
        ? '旅人（${_elementLabel(elementKey)}）'
        : name;
    final sp = a['specialProp'] as String?;

    final expected = weightProfiles[id] ??
        _infer(sp, displayName, nameOverrides: nameOverrides);
    final current = _infer(sp, displayName, nameOverrides: nameOverrides);

    byType[expected] = (byType[expected] ?? 0) + 1;

    if (current != expected) {
      currentWrong.add(
        '$displayName ($id): 現在=$current 期待=$expected specialProp=$sp',
      );
    }
  }

  print('=== 全キャラ取得基準 検証 (${byType.values.fold(0, (a, b) => a + b)}体) ===\n');
  print('期待値の内訳:');
  for (final e in byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) {
    print('  ${e.key}: ${e.value}体');
  }

  print('\n--- 現在のモバイル実装との不一致 (${currentWrong.length}体) ---');
  if (currentWrong.isEmpty) {
    print('なし（すべて一致）');
  } else {
    for (final line in currentWrong) {
      print('  $line');
    }
  }

  client.close();
}

Future<Map<String, String>> _loadNameOverridesFromJson() async {
  final file = File('assets/config/artifact_score_type_overrides.json');
  final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final overrides = decoded['overrides'] as List<dynamic>? ?? [];
  return {
    for (final raw in overrides)
      if (raw is Map<String, dynamic> && raw['name'] != null)
        raw['name'] as String: raw['scoreType'] as String,
  };
}

Future<Map<String, String>> _loadWeightProfilesFromJson() async {
  final file = File('assets/config/artifact_score_weights.json');
  if (!await file.exists()) return {};
  final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  final profiles = decoded['profiles'] as List<dynamic>? ?? [];
  final result = <String, String>{};
  for (final raw in profiles) {
    if (raw is! Map<String, dynamic>) continue;
    final id = raw['characterId'] as String?;
    final weightsJson = raw['weights'] as Map<String, dynamic>?;
    if (id == null || weightsJson == null) continue;
    final weights = ArtifactStatWeights.fromJson(weightsJson);
    final type = inferArtifactScoreTypeFromWeights(weights);
    if (type != null) {
      result[id] = artifactScoreTypeToStorage(type);
    }
  }
  return result;
}

String _infer(
  String? specialProp,
  String name, {
  required Map<String, String> nameOverrides,
}) {
  if (nameOverrides.containsKey(name)) return nameOverrides[name]!;
  return switch (specialProp) {
    'FIGHT_PROP_HP_PERCENT' => 'hp',
    'FIGHT_PROP_DEFENSE_PERCENT' => 'def',
    'FIGHT_PROP_ELEMENT_MASTERY' => 'em',
    'FIGHT_PROP_CHARGE_EFFICIENCY' => 'recharge',
    'FIGHT_PROP_ATTACK_PERCENT' => 'atk',
    _ => 'atk',
  };
}

String _elementLabel(String elementKey) => switch (elementKey) {
      'Fire' => '炎',
      'Water' => '水',
      'Electric' => '雷',
      'Ice' => '氷',
      'Wind' => '風',
      'Rock' => '岩',
      'Grass' => '草',
      _ => elementKey,
    };
