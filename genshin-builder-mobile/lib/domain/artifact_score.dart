import 'artifact_score_weights.dart';
import 'models/master_models.dart';
import 'models/artifact_state.dart';

enum ArtifactScoreType { atk, hp, def, recharge, em }

const _defaultScoreType = ArtifactScoreType.atk;

bool isGenericMasterScoreType(String? raw) {
  final normalized = raw?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty || normalized == 'atk';
}

ArtifactScoreType resolveArtifactScoreType(
  MasterCharacter character, {
  Map<String, ArtifactScoreType>? nameOverrides,
}) {
  final fromDb = artifactScoreTypeFromString(character.scoreType);
  if (fromDb != null && !isGenericMasterScoreType(character.scoreType)) {
    return fromDb;
  }

  final fromName = nameOverrides?[character.name];
  if (fromName != null) return fromName;

  return fromDb ?? _defaultScoreType;
}

/// 同期時に Amber の specialProp と名前から scoreType を推定する。
/// Web版 `inferScoreType` と同等（recharge 対応を追加）。
/// [nameOverrides] は `artifact_score_type_overrides.json` を読み込んだマップ。
ArtifactScoreType inferScoreType(
  String? specialProp,
  String name, {
  Map<String, ArtifactScoreType>? nameOverrides,
}) {
  final fromName = nameOverrides?[name];
  if (fromName != null) return fromName;

  return switch (specialProp) {
    'FIGHT_PROP_HP_PERCENT' => ArtifactScoreType.hp,
    'FIGHT_PROP_DEFENSE_PERCENT' => ArtifactScoreType.def,
    'FIGHT_PROP_ELEMENT_MASTERY' => ArtifactScoreType.em,
    'FIGHT_PROP_CHARGE_EFFICIENCY' => ArtifactScoreType.recharge,
    'FIGHT_PROP_ATTACK_PERCENT' => ArtifactScoreType.atk,
    _ => _defaultScoreType,
  };
}

ArtifactScoreType? artifactScoreTypeFromString(String? raw) => switch (raw) {
  'atk' => ArtifactScoreType.atk,
  'hp' => ArtifactScoreType.hp,
  'def' => ArtifactScoreType.def,
  'recharge' || 'er' => ArtifactScoreType.recharge,
  'em' => ArtifactScoreType.em,
  _ => null,
};

String artifactScoreTypeToStorage(ArtifactScoreType type) => switch (type) {
  ArtifactScoreType.atk => 'atk',
  ArtifactScoreType.hp => 'hp',
  ArtifactScoreType.def => 'def',
  ArtifactScoreType.recharge => 'recharge',
  ArtifactScoreType.em => 'em',
};

const _userArtifactScoreTypePrefix = 'user:';

/// ユーザーが手動選択したスコア基準のみ永続化する。
String artifactScoreTypeToUserStorage(ArtifactScoreType type) =>
    '$_userArtifactScoreTypePrefix${artifactScoreTypeToStorage(type)}';

ArtifactScoreType? userArtifactScoreTypeFromStorage(String? raw) {
  if (raw == null || !raw.startsWith(_userArtifactScoreTypePrefix)) {
    return null;
  }
  return artifactScoreTypeFromString(
    raw.substring(_userArtifactScoreTypePrefix.length),
  );
}

ArtifactScoreType? inferArtifactScoreTypeFromWeights(
  ArtifactStatWeights weights,
) {
  for (final type in ArtifactScoreType.values) {
    if (_sameWeights(weights, scoreWeightsForType(type))) {
      return type;
    }
  }
  return null;
}

double calcArtifactPieceScore(ArtifactPiece piece, ArtifactScoreType type) {
  return calcArtifactPieceScoreWithWeights(piece, scoreWeightsForType(type));
}

ArtifactStatWeights scoreWeightsForType(ArtifactScoreType type) =>
    switch (type) {
      ArtifactScoreType.atk => const ArtifactStatWeights(
        critRate: 2,
        critDamage: 1,
        atkPercent: 1,
        hpPercent: 0,
        defPercent: 0,
        elementalMastery: 0,
        energyRecharge: 0,
      ),
      ArtifactScoreType.hp => const ArtifactStatWeights(
        critRate: 2,
        critDamage: 1,
        atkPercent: 0,
        hpPercent: 1,
        defPercent: 0,
        elementalMastery: 0,
        energyRecharge: 0,
      ),
      ArtifactScoreType.def => const ArtifactStatWeights(
        critRate: 2,
        critDamage: 1,
        atkPercent: 0,
        hpPercent: 0,
        defPercent: 1,
        elementalMastery: 0,
        energyRecharge: 0,
      ),
      ArtifactScoreType.recharge => const ArtifactStatWeights(
        critRate: 2,
        critDamage: 1,
        atkPercent: 0,
        hpPercent: 0,
        defPercent: 0,
        elementalMastery: 0,
        energyRecharge: 1,
      ),
      ArtifactScoreType.em => const ArtifactStatWeights(
        critRate: 2,
        critDamage: 1,
        atkPercent: 0,
        hpPercent: 0,
        defPercent: 0,
        elementalMastery: 0.25,
        energyRecharge: 0,
      ),
    };

double calcArtifactPieceScoreWithWeights(
  ArtifactPiece piece,
  ArtifactStatWeights weights,
) {
  var score = 0.0;
  for (final sub in piece.substats) {
    switch (sub.stat) {
      case '会心率':
        score += sub.value * weights.critRate;
        break;
      case '会心ダメージ':
        score += sub.value * weights.critDamage;
        break;
      case '攻撃力%':
        score += sub.value * weights.atkPercent;
        break;
      case 'HP%':
        score += sub.value * weights.hpPercent;
        break;
      case '防御力%':
        score += sub.value * weights.defPercent;
        break;
      case '元素チャージ効率':
        score += sub.value * weights.energyRecharge;
        break;
      case '元素熟知':
        score += sub.value * weights.elementalMastery;
        break;
      default:
        break;
    }
  }
  return _round1(score);
}

double calcArtifactTotalScore(ArtifactState artifacts, ArtifactScoreType type) {
  return calcArtifactTotalScoreWithWeights(
    artifacts,
    scoreWeightsForType(type),
  );
}

double calcArtifactTotalScoreWithWeights(
  ArtifactState artifacts,
  ArtifactStatWeights weights,
) {
  var total = 0.0;
  for (final slot in ArtifactSlotKey.values) {
    total += calcArtifactPieceScoreWithWeights(
      artifacts[slot] ?? createEmptyArtifactPiece(),
      weights,
    );
  }
  return _round1(total);
}

double _round1(double value) => (value * 10).roundToDouble() / 10;

bool _sameWeights(ArtifactStatWeights a, ArtifactStatWeights b) {
  const epsilon = 0.000001;
  bool close(double x, double y) => (x - y).abs() < epsilon;
  return close(a.critRate, b.critRate) &&
      close(a.critDamage, b.critDamage) &&
      close(a.atkPercent, b.atkPercent) &&
      close(a.hpPercent, b.hpPercent) &&
      close(a.defPercent, b.defPercent) &&
      close(a.elementalMastery, b.elementalMastery) &&
      close(a.energyRecharge, b.energyRecharge);
}
