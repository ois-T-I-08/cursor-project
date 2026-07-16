import 'package:http/http.dart' as http;

import '../../domain/models/calculation_models.dart';
import '../../domain/weapon_exp.dart';
import '../amber/amber_constants.dart';
import '../config/remote_json_fetch.dart';

const _expMaterialIds = <String, List<String>>{
  'character': ['104001', '104002', '104003'],
  'weapon': ['104011', '104012', '104013'],
};

const _concurrency = 4;
const _requestDelayMs = 100;

/// Project Amber v2 から突破・天賦・武器 upgrade を取得（Web `amber-upgrade.ts` 相当）
class AmberUpgradeApi {
  AmberUpgradeApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 20);
  static const _maxBodyBytes = 2 * 1024 * 1024;

  Future<Map<String, dynamic>> _fetchV2(String path) async {
    final json = await fetchRemoteJsonMap(
      client: _client,
      url: '$amberBaseUrl/api/v2/jp$path',
      kind: 'amber-upgrade',
      timeout: _timeout,
      maxBytes: _maxBodyBytes,
    );
    if (json['response'] != 200) {
      throw const FormatException('Invalid Amber response status');
    }
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid Amber upgrade payload');
    }
    return data;
  }

  List<PromoteStage> parsePromotes(List<dynamic>? promotes) {
    return (promotes ?? []).map((raw) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid promote entry');
      }
      final p = raw;
      final costItems = <String, int>{};
      final costs = p['costItems'];
      if (costs is Map) {
        costs.forEach((key, value) {
          final count = (value as num?)?.toInt();
          if (count == null || count < 0) {
            throw const FormatException('Invalid promote material count');
          }
          costItems['$key'] = count;
        });
      } else if (costs is List) {
        for (final item in costs) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Invalid promote material');
          }
          final id = '${item['id']}';
          final count = (item['count'] as num?)?.toInt();
          if (id.isEmpty || id == 'null' || count == null || count < 0) {
            throw const FormatException('Invalid promote material');
          }
          costItems[id] = count;
        }
      }
      final promoteLevel = (p['promoteLevel'] as num?)?.toInt() ?? 0;
      final unlockMaxLevel = (p['unlockMaxLevel'] as num?)?.toInt() ?? 90;
      final coinCost = (p['coinCost'] as num?)?.toInt() ?? 0;
      if (promoteLevel < 0 || unlockMaxLevel < 1 || coinCost < 0) {
        throw const FormatException('Invalid promote values');
      }
      return PromoteStage(
        promoteLevel: promoteLevel,
        unlockMaxLevel: unlockMaxLevel,
        costItems: costItems,
        coinCost: coinCost,
        requiredPlayerLevel: (p['requiredPlayerLevel'] as num?)?.toInt(),
      );
    }).toList();
  }

  List<TalentLevelUpgrade> parseTalentUpgrades(Map<String, dynamic>? promote) {
    if (promote == null) return [];
    final entries =
        promote.entries
            .map((e) => e.value as Map<String, dynamic>)
            .where((p) => p['level'] != null)
            .toList()
          ..sort(
            (a, b) =>
                ((a['level'] as num?)?.toInt() ?? 0) -
                ((b['level'] as num?)?.toInt() ?? 0),
          );

    return entries.map((p) {
      final costItems = <String, int>{};
      final costs = p['costItems'];
      if (costs is Map) {
        costs.forEach((key, value) {
          final count = (value as num?)?.toInt();
          if (count == null || count < 0) {
            throw const FormatException('Invalid talent material count');
          }
          costItems['$key'] = count;
        });
      }
      final level = (p['level'] as num?)?.toInt() ?? 0;
      final coinCost = (p['coinCost'] as num?)?.toInt() ?? 0;
      if (level < 1 || coinCost < 0) {
        throw const FormatException('Invalid talent values');
      }
      return TalentLevelUpgrade(
        level: level,
        costItems: costItems,
        coinCost: coinCost,
      );
    }).toList();
  }

  Future<
    ({
      List<PromoteStage> promotes,
      Map<String, List<TalentLevelUpgrade>> talents,
    })?
  >
  fetchCharacterUpgrade(String characterId) async {
    final data = await _fetchV2('/avatar/$characterId');

    if (data['talent'] is! Map<String, dynamic> ||
        data['upgrade'] is! Map<String, dynamic>) {
      throw const FormatException('Missing character upgrade fields');
    }
    final talentRaw = data['talent'] as Map<String, dynamic>;
    final keys =
        talentRaw.keys.toList()
          ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));

    final talents = <String, List<TalentLevelUpgrade>>{};
    var skillIndex = 0;
    for (final key in keys) {
      final t = talentRaw[key] as Map<String, dynamic>;
      final type = (t['type'] as num?)?.toInt();
      if (type != 0 && type != 1) continue;
      final upgrades = parseTalentUpgrades(
        t['promote'] as Map<String, dynamic>?,
      );
      if (upgrades.isNotEmpty) {
        talents['skill_$skillIndex'] = upgrades;
        skillIndex++;
      }
      if (skillIndex >= 3) break;
    }

    final upgrade = data['upgrade'] as Map<String, dynamic>;
    final promotes = parsePromotes(upgrade['promote'] as List<dynamic>?);
    if (promotes.isEmpty) {
      throw const FormatException('Empty character promotes');
    }

    return (promotes: promotes, talents: talents);
  }

  Future<({List<PromoteStage> promotes, List<String> levelUpItemIds})?>
  fetchWeaponUpgrade(String weaponId) async {
    final data = await _fetchV2('/weapon/$weaponId');

    // マネキン武器など upgrade 未実装はスキップ（同期全体を落とさない）
    if (data['upgrade'] is! Map<String, dynamic>) {
      return null;
    }
    final upgrade = data['upgrade'] as Map<String, dynamic>;
    final promoteRaw = upgrade['promote'];
    if (promoteRaw is! List) {
      return null;
    }
    final promotes = parsePromotes(promoteRaw);
    if (promotes.isEmpty) {
      return null;
    }
    final items = data['items'] as Map<String, dynamic>?;
    final levelUpItemIds = parseWeaponEnhancementOreIds(items);

    return (promotes: promotes, levelUpItemIds: levelUpItemIds);
  }

  int? parseExpFromDescription(String description) {
    final match = RegExp(r'経験値(\d+)').firstMatch(description);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Future<List<({String materialId, int exp, String targetType})>>
  fetchLevelUpMaterials() async {
    final result = <({String materialId, int exp, String targetType})>[];

    for (final targetType in ['character', 'weapon']) {
      for (final id in _expMaterialIds[targetType]!) {
        final detail = await _fetchV2('/material/$id');
        final description = detail['description'] as String? ?? '';
        final exp = parseExpFromDescription(description);
        if (exp == null) continue;
        result.add((materialId: id, exp: exp, targetType: targetType));
      }
    }

    return result;
  }

  Future<List<T>> mapWithConcurrency<T>(
    List<String> ids,
    Future<T?> Function(String id) fn, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = <T>[];
    var index = 0;
    var completed = 0;
    final total = ids.length;

    Future<void> worker() async {
      while (index < ids.length) {
        final i = index++;
        await Future<void>.delayed(
          const Duration(milliseconds: _requestDelayMs),
        );
        final value = await fn(ids[i]);
        if (value != null) results.add(value);
        completed++;
        onProgress?.call(completed, total);
      }
    }

    if (ids.isEmpty) {
      onProgress?.call(0, 0);
      return results;
    }

    await Future.wait(
      List.generate(
        ids.length < _concurrency ? ids.length : _concurrency,
        (_) => worker(),
      ),
    );
    return results;
  }

  void dispose() => _client.close();
}

/// キャラ upgrade 同期結果
typedef CharacterUpgradeSync =
    ({
      String characterId,
      List<PromoteStage> promotes,
      Map<String, List<TalentLevelUpgrade>> talents,
    });

/// 武器 upgrade 同期結果
typedef WeaponUpgradeSync =
    ({
      String weaponId,
      List<PromoteStage> promotes,
      List<String> levelUpItemIds,
    });
