import '../../../data/hoyolab/models/game_record.dart';
import '../../../domain/level_config.dart';

/// 天賦セクションのアコーディオン要約テキスト
String buildTalentSummaryText({
  required int talentNormal,
  required int talentSkill,
  required int talentBurst,
}) {
  final allMax =
      talentNormal >= talentLevelMax &&
      talentSkill >= talentLevelMax &&
      talentBurst >= talentLevelMax;
  if (allMax) {
    return '最大強化済み · 通常$talentNormal / スキル$talentSkill / 爆発$talentBurst';
  }
  return '通常$talentNormal / スキル$talentSkill / 爆発$talentBurst';
}

/// HoYoLAB セクションのアコーディオン要約テキスト
String buildHoyolabSummaryText(HoyolabCharacterBuild? build) {
  if (build == null || !build.isOwned) {
    return '未連携または未所持';
  }
  final parts = <String>['Lv.${build.level}'];
  if (build.constellation > 0) {
    parts.add('凸${build.constellation}');
  }
  if (build.weapon != null && build.weapon!.name.isNotEmpty) {
    parts.add(build.weapon!.name);
  }
  return parts.join(' · ');
}
