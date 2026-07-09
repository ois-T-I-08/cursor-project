import 'dart:convert';
import 'dart:io';

import 'package:genshin_builder_mobile/domain/artifact_score.dart';

/// 新キャラの Amber specialProp と推定スコア基準を確認する。
/// 名前は下の `targetName` を書き換えて実行。
const targetName = 'コロンビーナ';

Future<void> main() async {
  final nameOverrides = await _loadNameOverridesFromJson();

  final client = HttpClient();
  final res = await client.getUrl(
    Uri.parse('https://gi.yatta.moe/api/v2/jp/avatar'),
  );
  final body = await (await res.close()).transform(utf8.decoder).join();
  final items = (jsonDecode(body)['data'] as Map)['items'] as Map;

  for (final raw in items.values) {
    final a = raw as Map<String, dynamic>;
    final name = a['name'] as String? ?? '';
    if (!name.contains(targetName) &&
        !name.toLowerCase().contains(targetName.toLowerCase())) {
      continue;
    }
    final sp = a['specialProp'];
    final overrides = {
      for (final e in nameOverrides.entries)
        e.key: artifactScoreTypeFromString(e.value)!,
    };
    final inferred = inferScoreType(
      sp as String?,
      name,
      nameOverrides: overrides,
    );
    print('id: ${a['id']}');
    print('name: $name');
    print('specialProp: $sp');
    print('inferScoreType: ${artifactScoreTypeToStorage(inferred)}');
    if (nameOverrides.containsKey(name)) {
      print('json override: ${nameOverrides[name]}');
    } else {
      print('json override: (なし — specialProp と一致していれば追加不要)');
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
