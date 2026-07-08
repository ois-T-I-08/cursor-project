import '../../domain/models/calculation_models.dart';

/// 突破・天賦 JSON の共有シリアライズ（sqflite / Drift 共通）
class UpgradeSerde {
  UpgradeSerde._();

  static Map<String, dynamic> promoteToJson(PromoteStage p) => {
        'promoteLevel': p.promoteLevel,
        'unlockMaxLevel': p.unlockMaxLevel,
        'costItems': p.costItems,
        'coinCost': p.coinCost,
        'requiredPlayerLevel': p.requiredPlayerLevel,
      };

  static PromoteStage promoteFromJson(Map<String, dynamic> j) => PromoteStage(
        promoteLevel: j['promoteLevel'] as int,
        unlockMaxLevel: j['unlockMaxLevel'] as int,
        costItems: Map<String, int>.from(j['costItems'] as Map),
        coinCost: j['coinCost'] as int,
        requiredPlayerLevel: j['requiredPlayerLevel'] as int?,
      );

  static Map<String, dynamic> talentToJson(TalentLevelUpgrade t) => {
        'level': t.level,
        'costItems': t.costItems,
        'coinCost': t.coinCost,
      };

  static TalentLevelUpgrade talentFromJson(Map<String, dynamic> j) =>
      TalentLevelUpgrade(
        level: j['level'] as int,
        costItems: Map<String, int>.from(j['costItems'] as Map),
        coinCost: j['coinCost'] as int,
      );
}
