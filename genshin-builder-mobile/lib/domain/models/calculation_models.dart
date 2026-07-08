/// ドメインモデル（計算入出力）
library;

class PromoteStage {
  const PromoteStage({
    required this.promoteLevel,
    required this.unlockMaxLevel,
    required this.costItems,
    required this.coinCost,
    this.requiredPlayerLevel,
  });

  final int promoteLevel;
  final int unlockMaxLevel;
  final Map<String, int> costItems;
  final int coinCost;
  final int? requiredPlayerLevel;
}

class MaterialCost {
  const MaterialCost({required this.materialId, required this.count});

  final String materialId;
  final int count;
}

class LevelUpMaterialSuggestion {
  const LevelUpMaterialSuggestion({
    required this.materialId,
    required this.name,
    required this.count,
  });

  final String materialId;
  final String name;
  final int count;
}

class NextStageRequirements {
  const NextStageRequirements({
    required this.fromLevel,
    required this.toLevel,
    required this.needsAscension,
    required this.materials,
    required this.mora,
    required this.expTotal,
    required this.levelUpMaterials,
  });

  final int fromLevel;
  final int toLevel;
  final bool needsAscension;
  final List<MaterialCost> materials;
  final int mora;
  final int expTotal;
  final List<LevelUpMaterialSuggestion> levelUpMaterials;
}

class AscensionStageInfo {
  const AscensionStageInfo({
    required this.level,
    required this.promoteLevel,
    required this.requiresAscension,
    required this.materials,
    required this.mora,
    this.requiredPlayerLevel,
  });

  final int level;
  final int promoteLevel;
  final bool requiresAscension;
  final List<MaterialCost> materials;
  final int mora;
  final int? requiredPlayerLevel;
}

class TalentLevelUpgrade {
  const TalentLevelUpgrade({
    required this.level,
    required this.costItems,
    required this.coinCost,
  });

  final int level;
  final Map<String, int> costItems;
  final int coinCost;
}

class NextTalentRequirements {
  const NextTalentRequirements({
    required this.fromLevel,
    required this.toLevel,
    required this.materials,
    required this.mora,
  });

  final int fromLevel;
  final int toLevel;
  final List<MaterialCost> materials;
  final int mora;
}

/// DB 同期データのキャッシュ（UpgradeDataCache 相当）
class UpgradeDataCache {
  const UpgradeDataCache({
    this.levelExpSegments = const [],
    this.levelUpMaterials = const [],
  });

  final List<LevelExpSegment> levelExpSegments;
  final List<LevelUpMaterialMaster> levelUpMaterials;
}

class LevelExpSegment {
  const LevelExpSegment({
    required this.id,
    required this.targetType,
    required this.rarity,
    required this.fromLevel,
    required this.toLevel,
    required this.expRequired,
    this.moraRequired = 0,
  });

  final String id;
  final String targetType;
  final int rarity;
  final int fromLevel;
  final int toLevel;
  final int expRequired;
  final int moraRequired;
}

class LevelUpMaterialMaster {
  const LevelUpMaterialMaster({
    required this.materialId,
    required this.name,
    required this.exp,
    required this.targetType,
  });

  final String materialId;
  final String name;
  final int exp;
  final String targetType;
}
