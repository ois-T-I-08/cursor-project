import 'models/master_models.dart';
import 'artifact_score.dart';

/// 武器一覧の並び替え基準
enum WeaponListSortMode {
  /// 公開ビルドの武器使用率（人気順）。未取得時はローカル推定にフォールバック
  popularity,

  /// レア度 高→低
  rarityDesc,

  /// 基礎攻撃力 高→低
  baseAttackDesc,
}

extension WeaponListSortModeLabel on WeaponListSortMode {
  String get label => switch (this) {
    WeaponListSortMode.popularity => '人気順（使用率）',
    WeaponListSortMode.rarityDesc => 'レア度順',
    WeaponListSortMode.baseAttackDesc => '基礎攻撃力順',
  };
}

/// 一覧・ソート用の武器行データ（MasterWeapon + ソート用メタ）
///
/// 将来のフィルター（所持・未所持など）もこのエントリを対象にする。
class WeaponListEntry {
  const WeaponListEntry({
    required this.weapon,
    this.baseAttack = 0,
    this.recommendScore = 0,
    this.specialProp,
    this.usageRate,
    this.owned,
  });

  final MasterWeapon weapon;

  /// Lv.90 時点の基礎攻撃力（未取得時は 0）
  final double baseAttack;

  /// 人気順用スコア（大きいほど上位）。使用率 or ローカル推定
  final double recommendScore;

  /// FIGHT_PROP_*（サブステ）。ローカル推定に使用
  final String? specialProp;

  /// 公開ビルド上の使用率（0〜1）。未取得時は null
  final double? usageRate;

  /// 所持状況（将来フィルター用。現状は null = 不明）
  final bool? owned;

  String get id => weapon.id;
  String get weaponName => weapon.name;
  int get rarity => weapon.rarity;

  WeaponListEntry copyWith({
    MasterWeapon? weapon,
    double? baseAttack,
    double? recommendScore,
    String? specialProp,
    double? usageRate,
    bool? owned,
  }) => WeaponListEntry(
    weapon: weapon ?? this.weapon,
    baseAttack: baseAttack ?? this.baseAttack,
    recommendScore: recommendScore ?? this.recommendScore,
    specialProp: specialProp ?? this.specialProp,
    usageRate: usageRate ?? this.usageRate,
    owned: owned ?? this.owned,
  );
}

/// 将来のフィルター条件（未使用でもパイプラインに載せておく）
class WeaponListFilter {
  const WeaponListFilter({
    this.weaponType,
    this.minRarity,
    this.ownedOnly = false,
    this.excludeUnowned = false,
  });

  final String? weaponType;
  final int? minRarity;
  final bool ownedOnly;
  final bool excludeUnowned;

  static const none = WeaponListFilter();
}

/// 使用率（0〜1）から人気スコアを算出。同率はレア度・基礎ATKでタイブレーク。
double computeWeaponPopularityScore({
  required double usageRate,
  required int rarity,
  double baseAttack = 0,
}) {
  return usageRate * 1000 + rarity * 0.1 + baseAttack / 10000;
}

/// ローカル推定スコア（使用率未取得時のフォールバック）。`scoreOverride` で差し替え可。
double computeWeaponRecommendScore({
  required MasterWeapon weapon,
  required MasterCharacter character,
  String? specialProp,
  double baseAttack = 0,
  double? scoreOverride,
}) {
  if (scoreOverride != null) return scoreOverride;

  var score = weapon.rarity * 1000.0;
  final charScoreType = resolveArtifactScoreType(character);
  final weaponScoreType = inferScoreType(specialProp, weapon.name);

  if (weaponScoreType == charScoreType) {
    score += 500;
  }

  // 攻撃型キャラには会心サブをやや優遇
  if (charScoreType == ArtifactScoreType.atk &&
      (specialProp == 'FIGHT_PROP_CRITICAL' ||
          specialProp == 'FIGHT_PROP_CRITICAL_HURT')) {
    score += 200;
  }

  // 基礎攻撃力を弱いタイブレークに使う
  score += baseAttack / 10;

  return score;
}

List<WeaponListEntry> filterWeaponList(
  List<WeaponListEntry> entries,
  WeaponListFilter filter,
) {
  return entries.where((e) {
    if (filter.weaponType != null && e.weapon.weaponType != filter.weaponType) {
      return false;
    }
    if (filter.minRarity != null && e.rarity < filter.minRarity!) {
      return false;
    }
    if (filter.ownedOnly && e.owned != true) return false;
    if (filter.excludeUnowned && e.owned == false) return false;
    return true;
  }).toList();
}

List<WeaponListEntry> sortWeaponList(
  List<WeaponListEntry> entries,
  WeaponListSortMode mode, {
  String? selectedWeaponId,
}) {
  final list = [...entries];
  int cmpName(WeaponListEntry a, WeaponListEntry b) =>
      a.weaponName.compareTo(b.weaponName);

  list.sort((a, b) {
    // 装備中は常に最上位（見つけやすい）
    if (selectedWeaponId != null && selectedWeaponId.isNotEmpty) {
      final aEq = a.id == selectedWeaponId;
      final bEq = b.id == selectedWeaponId;
      if (aEq != bEq) return aEq ? -1 : 1;
    }

    switch (mode) {
      case WeaponListSortMode.popularity:
        final byScore = b.recommendScore.compareTo(a.recommendScore);
        if (byScore != 0) return byScore;
        final byRarity = b.rarity.compareTo(a.rarity);
        if (byRarity != 0) return byRarity;
        return cmpName(a, b);
      case WeaponListSortMode.rarityDesc:
        final byRarity = b.rarity.compareTo(a.rarity);
        if (byRarity != 0) return byRarity;
        final byAtk = b.baseAttack.compareTo(a.baseAttack);
        if (byAtk != 0) return byAtk;
        return cmpName(a, b);
      case WeaponListSortMode.baseAttackDesc:
        final byAtk = b.baseAttack.compareTo(a.baseAttack);
        if (byAtk != 0) return byAtk;
        final byRarity = b.rarity.compareTo(a.rarity);
        if (byRarity != 0) return byRarity;
        return cmpName(a, b);
    }
  });
  return list;
}

/// フィルター → ソートの一連処理
List<WeaponListEntry> prepareWeaponList({
  required List<WeaponListEntry> entries,
  required WeaponListSortMode sortMode,
  WeaponListFilter filter = WeaponListFilter.none,
  String? selectedWeaponId,
}) {
  final filtered = filterWeaponList(entries, filter);
  return sortWeaponList(filtered, sortMode, selectedWeaponId: selectedWeaponId);
}
