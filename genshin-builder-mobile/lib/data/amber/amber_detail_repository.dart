/// Project Amber 詳細データ（スキル説明・倍率表・ステータス計算用曲線）
///
/// キャラ詳細画面のスキル詳細表示・想定ステータス計算に使う。
/// 取得結果はメモリキャッシュし、失敗時は null を返して画面側で
/// 「取得できません」表示にフォールバックする（DB には保存しない）。
library;

import '../../domain/character_stats.dart';
import '../../domain/models/amber_detail_models.dart';
import 'amber_api.dart';
import 'amber_constants.dart';

export '../../domain/models/amber_detail_models.dart';

// ---------------------------------------------------------
// パース補助
// ---------------------------------------------------------

/// API 説明文の `<color=...>` 等を除去して平文にする（Web `stripMarkup` 相当）
String stripAmberMarkup(String text) {
  return text
      .replaceAll(RegExp(r'<color=[^>]*>'), '')
      .replaceAll('</color>', '')
      .replaceAll('<i>', '')
      .replaceAll('</i>', '')
      .replaceAll(r'\n', '\n');
}

final _paramPattern = RegExp(r'\{param(\d+):([^}]+)\}');

/// `{param1:F1P}` 形式のプレースホルダを params の値で置換する。
/// `F<d>` = 小数桁数, `P` = %表記（×100）, `I` = 整数。
String _interpolateParams(String template, List<double> params) {
  return template.replaceAllMapped(_paramPattern, (m) {
    final index = int.parse(m.group(1)!) - 1;
    if (index < 0 || index >= params.length) return '-';
    final format = m.group(2)!;
    final isPercent = format.contains('P');
    final value = isPercent ? params[index] * 100 : params[index];

    final decimalsMatch = RegExp(r'F(\d)').firstMatch(format);
    final int decimals;
    if (decimalsMatch != null) {
      decimals = int.parse(decimalsMatch.group(1)!);
    } else if (format.contains('I')) {
      decimals = 0;
    } else {
      decimals = value == value.roundToDouble() ? 0 : 1;
    }

    final text = value.toStringAsFixed(decimals);
    return isPercent ? '$text%' : text;
  });
}

List<TalentStatRow> _parseLevelRows(
  List<dynamic>? descriptions,
  List<double> params,
) {
  if (descriptions == null) return const [];
  final rows = <TalentStatRow>[];
  for (final raw in descriptions) {
    final text = '$raw';
    if (text.trim().isEmpty || text.trim() == '|') continue;
    final sep = text.indexOf('|');
    if (sep <= 0) continue;
    final label = text.substring(0, sep).trim();
    final valueTemplate = text.substring(sep + 1).trim();
    if (label.isEmpty || valueTemplate.isEmpty) continue;
    rows.add(
      TalentStatRow(
        label: label,
        value: _interpolateParams(valueTemplate, params),
      ),
    );
  }
  return rows;
}

List<double> _asDoubleList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((e) => e is num ? e.toDouble() : 0.0).toList();
}

double _asDouble(dynamic raw) => raw is num ? raw.toDouble() : 0.0;

/// upgrade JSON + 曲線データ → 計算用モデル（Web `buildStats` 相当）
AvatarStatsData? _buildStatsData(
  Map<String, dynamic>? upgrade,
  Map<String, dynamic>? curveData,
) {
  final propList = upgrade?['prop'] as List<dynamic>?;
  if (propList == null || curveData == null) return null;

  const maxLevel = 90;

  List<double> curveValuesFor(String curveType) {
    final values = <double>[];
    for (var level = 1; level <= maxLevel; level++) {
      final entry = curveData['$level'] as Map<String, dynamic>?;
      final infos = entry?['curveInfos'] as Map<String, dynamic>?;
      values.add(_asDouble(infos?[curveType] ?? 1));
    }
    return values;
  }

  final props = <StatCurveProp>[];
  for (final raw in propList) {
    final prop = raw as Map<String, dynamic>;
    final propType = prop['propType'] as String?;
    final curveType = prop['type'] as String?;
    if (propType == null || curveType == null) continue;
    props.add(
      StatCurveProp(
        propType: propType,
        initValue: _asDouble(prop['initValue']),
        curveValues: curveValuesFor(curveType),
      ),
    );
  }

  final promotes = <StatPromote>[];
  for (final raw in (upgrade?['promote'] as List<dynamic>? ?? [])) {
    final promote = raw as Map<String, dynamic>;
    final addPropsRaw = promote['addProps'] as Map<String, dynamic>? ?? {};
    promotes.add(
      StatPromote(
        promoteLevel: (promote['promoteLevel'] as num?)?.toInt() ?? 0,
        unlockMaxLevel:
            (promote['unlockMaxLevel'] as num?)?.toInt() ?? maxLevel,
        addProps: {
          for (final e in addPropsRaw.entries) e.key: _asDouble(e.value),
        },
      ),
    );
  }

  return AvatarStatsData(props: props, promotes: promotes);
}

// ---------------------------------------------------------
// リポジトリ
// ---------------------------------------------------------

class AmberDetailRepository {
  AmberDetailRepository({AmberApi? api}) : _api = api ?? AmberApi();

  final AmberApi _api;

  Map<String, dynamic>? _avatarCurveCache;
  Map<String, dynamic>? _weaponCurveCache;
  List<ArtifactSetDetail>? _artifactSetsCache;
  final _avatarDetailCache = <String, AvatarDetailData?>{};
  final _weaponStatsCache = <String, WeaponStatsData?>{};
  final _weaponDetailCache = <String, WeaponDetailData?>{};

  Future<Map<String, dynamic>?> _avatarCurve() async {
    if (_avatarCurveCache != null) return _avatarCurveCache;
    try {
      _avatarCurveCache = await _api.fetchStaticData('/avatarCurve');
    } catch (_) {
      return null;
    }
    return _avatarCurveCache;
  }

  Future<Map<String, dynamic>?> _weaponCurve() async {
    if (_weaponCurveCache != null) return _weaponCurveCache;
    try {
      _weaponCurveCache = await _api.fetchStaticData('/weaponCurve');
    } catch (_) {
      return null;
    }
    return _weaponCurveCache;
  }

  /// キャラのスキル詳細 + ステータス計算用データを取得する（失敗時 null）
  Future<AvatarDetailData?> getAvatarDetail(String characterId) async {
    if (_avatarDetailCache.containsKey(characterId)) {
      return _avatarDetailCache[characterId];
    }
    AvatarDetailData? result;
    try {
      final json = await _api.fetchAvatarDetail(characterId);
      final curve = await _avatarCurve();
      result = _parseAvatarDetail(json, curve);
    } catch (_) {
      result = null;
    }
    // 失敗はキャッシュしない（次回リトライできるようにする）
    if (result != null) {
      _avatarDetailCache[characterId] = result;
    }
    return result;
  }

  /// 武器のステータス計算用データを取得する（失敗時 null）
  Future<WeaponStatsData?> getWeaponStats(String weaponId) async {
    if (weaponId.isEmpty) return null;
    if (_weaponStatsCache.containsKey(weaponId)) {
      return _weaponStatsCache[weaponId];
    }
    final detail = await getWeaponDetail(weaponId);
    return detail?.stats;
  }

  /// 武器の詳細（効果・精錬含む）を取得する（失敗時 null）
  Future<WeaponDetailData?> getWeaponDetail(String weaponId) async {
    if (weaponId.isEmpty) return null;
    if (_weaponDetailCache.containsKey(weaponId)) {
      return _weaponDetailCache[weaponId];
    }
    WeaponDetailData? result;
    try {
      final json = await _api.fetchWeaponDetail(weaponId);
      final curve = await _weaponCurve();
      final statsData = _buildStatsData(
        json['upgrade'] as Map<String, dynamic>?,
        curve,
      );
      if (statsData == null) {
        result = null;
      } else {
        final stats = WeaponStatsData(
          props: statsData.props,
          promotes: statsData.promotes,
        );
        final upgradeMap = json['upgrade'] as Map<String, dynamic>?;
        final props = upgradeMap?['prop'] as List<dynamic>? ?? [];
        String? subProp;
        for (final raw in props) {
          final prop = raw as Map<String, dynamic>;
          final type = prop['propType'] as String?;
          if (type != null && type != 'FIGHT_PROP_BASE_ATTACK') {
            subProp = type;
            break;
          }
        }

        final affixMap = json['affix'] as Map<String, dynamic>?;
        final affix =
            affixMap == null || affixMap.isEmpty
                ? null
                : affixMap.values.first as Map<String, dynamic>;
        final upgrade = affix?['upgrade'] as Map<String, dynamic>? ?? {};
        final effectDescriptions =
            upgrade.keys.map((k) => int.tryParse(k) ?? 0).toList()..sort();
        final descriptions =
            effectDescriptions
                .map((k) => stripAmberMarkup('${upgrade['$k'] ?? ''}'))
                .where((s) => s.isNotEmpty)
                .toList();

        final typeKey = json['type'] as String? ?? '';
        final weaponType = weaponTypeMap[typeKey] ?? typeKey;
        final icon = json['icon'] as String?;

        result = WeaponDetailData(
          id: '${json['id']}',
          name: json['name'] as String? ?? '',
          rarity: (json['rank'] as num?)?.toInt() ?? 4,
          weaponType: weaponType,
          weaponTypeLabel: weaponTypeLabelMap[weaponType] ?? weaponType,
          iconUrl: icon == null || icon.isEmpty ? null : buildIconUrl(icon),
          stats: stats,
          subStatProp: subProp,
          subStatName: subProp == null ? null : fightPropLabel(subProp),
          effectName: affix?['name'] as String?,
          effectDescriptions: descriptions,
        );
        _weaponStatsCache[weaponId] = stats;
      }
    } catch (_) {
      result = null;
    }
    if (result != null) {
      _weaponDetailCache[weaponId] = result;
    }
    return result;
  }

  /// 聖遺物セット一覧（失敗時は空）
  Future<List<ArtifactSetDetail>> getArtifactSets() async {
    if (_artifactSetsCache != null) return _artifactSetsCache!;
    try {
      final items = await _api.fetchReliquaryItems();
      final sets = <ArtifactSetDetail>[];
      for (final raw in items.values) {
        final set = raw as Map<String, dynamic>;
        final name = set['name'] as String?;
        if (name == null || name.isEmpty) continue;
        final affixList = set['affixList'] as Map<String, dynamic>?;
        final effects =
            affixList == null
                ? const <String>[]
                : affixList.values
                    .map((e) => stripAmberMarkup('$e'))
                    .where((s) => s.isNotEmpty)
                    .toList();
        final icon = set['icon'] as String?;
        final sortOrder = (set['sortOrder'] as num?)?.toInt() ?? 0;
        final id = '${set['id']}';
        final route = (set['route'] as String?)?.trim() ?? '';
        sets.add(
          ArtifactSetDetail(
            id: id,
            name: name,
            iconUrl: icon == null || icon.isEmpty ? null : buildIconUrl(icon),
            effects: effects,
            region: resolveArtifactSetRegion(id: id, sortOrder: sortOrder),
            sortOrder: sortOrder,
            route: route,
          ),
        );
      }
      sets.sort((a, b) {
        final regionCmp = artifactSetRegionOrder
            .indexOf(a.region)
            .compareTo(artifactSetRegionOrder.indexOf(b.region));
        if (regionCmp != 0) return regionCmp;
        return a.sortOrder.compareTo(b.sortOrder);
      });
      _artifactSetsCache = sets;
    } catch (_) {
      _artifactSetsCache = const [];
    }
    return _artifactSetsCache!;
  }

  /// セット名で聖遺物セット効果を探す
  Future<ArtifactSetDetail?> findArtifactSetByName(String setName) async {
    if (setName.isEmpty) return null;
    final sets = await getArtifactSets();
    for (final set in sets) {
      if (set.name == setName) return set;
    }
    return null;
  }

  AvatarDetailData _parseAvatarDetail(
    Map<String, dynamic> json,
    Map<String, dynamic>? curveData,
  ) {
    final talentMap = json['talent'] as Map<String, dynamic>? ?? {};
    final keys =
        talentMap.keys.toList()..sort(
          (a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0),
        );

    final actives = <Map<String, dynamic>>[];
    final passives = <Map<String, dynamic>>[];
    for (final key in keys) {
      final talent = talentMap[key] as Map<String, dynamic>;
      final type = (talent['type'] as num?)?.toInt() ?? -1;
      if (type == 0 || type == 1) {
        actives.add(talent);
      } else {
        passives.add(talent);
      }
    }

    const activeKinds = [
      TalentDetailKind.normal,
      TalentDetailKind.skill,
      TalentDetailKind.burst,
    ];

    TalentDetailData buildTalent(
      Map<String, dynamic> talent,
      TalentDetailKind kind,
    ) {
      final icon = talent['icon'] as String?;
      final levelStats = <int, List<TalentStatRow>>{};

      if (kind != TalentDetailKind.passive) {
        final promote = talent['promote'] as Map<String, dynamic>? ?? {};
        for (final entry in promote.values) {
          final data = entry as Map<String, dynamic>;
          final level = (data['level'] as num?)?.toInt();
          if (level == null) continue;
          final rows = _parseLevelRows(
            data['description'] as List<dynamic>?,
            _asDoubleList(data['params']),
          );
          if (rows.isNotEmpty) {
            levelStats[level] = rows;
          }
        }
      }

      return TalentDetailData(
        kind: kind,
        name: talent['name'] as String? ?? '',
        description: stripAmberMarkup(talent['description'] as String? ?? ''),
        iconUrl: icon == null || icon.isEmpty ? null : buildIconUrl(icon),
        levelStats: levelStats,
      );
    }

    final talents = <TalentDetailData>[
      for (var i = 0; i < actives.length && i < 3; i++)
        buildTalent(actives[i], activeKinds[i]),
      for (final passive in passives)
        buildTalent(passive, TalentDetailKind.passive),
    ];

    final constellationMap =
        json['constellation'] as Map<String, dynamic>? ?? {};
    final constellationKeys =
        constellationMap.keys.toList()..sort(
          (a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0),
        );
    final constellations = <ConstellationDetailData>[];
    for (var i = 0; i < constellationKeys.length && i < 6; i++) {
      final raw =
          constellationMap[constellationKeys[i]] as Map<String, dynamic>;
      final icon = raw['icon'] as String?;
      constellations.add(
        ConstellationDetailData(
          position: i + 1,
          name: raw['name'] as String? ?? '命ノ星座 第${i + 1}重',
          description: stripAmberMarkup(raw['description'] as String? ?? ''),
          iconUrl: icon == null || icon.isEmpty ? null : buildIconUrl(icon),
        ),
      );
    }

    return AvatarDetailData(
      talents: talents,
      constellations: constellations,
      stats: _buildStatsData(
        json['upgrade'] as Map<String, dynamic>?,
        curveData,
      ),
    );
  }

  void dispose() => _api.dispose();

  /// 聖遺物セット一覧キャッシュを破棄（再取得用）
  void clearArtifactSetsCache() {
    _artifactSetsCache = null;
  }
}
