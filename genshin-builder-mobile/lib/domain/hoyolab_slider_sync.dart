import 'level_progression.dart';
import 'talent_progression.dart';

/// HoYoLAB 天賦一覧から UI 用レベルを抽出する入力
class HoyolabTalentInput {
  const HoyolabTalentInput({required this.name, required this.level});

  final String name;
  final int level;
}

/// スライダーへ反映するスナップショット
class HoyolabSliderSnapshot {
  const HoyolabSliderSnapshot({
    required this.level,
    required this.talentNormal,
    required this.talentSkill,
    required this.talentBurst,
    this.promoteLevel = 0,
    this.constellation = 0,
    this.weaponId,
    this.weaponName,
    this.weaponLevel,
    this.weaponRefinement,
  });

  final int level;
  final int talentNormal;
  final int talentSkill;
  final int talentBurst;
  final int promoteLevel;
  final int constellation;
  final String? weaponId;
  final String? weaponName;
  final int? weaponLevel;
  final int? weaponRefinement;
}

/// HoYoLAB API の値をスライダー用に正規化
HoyolabSliderSnapshot buildHoyolabSliderSnapshot({
  required int level,
  required int promoteLevel,
  required int constellation,
  required List<HoyolabTalentInput> talents,
  String? weaponId,
  String? weaponName,
  int? weaponLevel,
  int? weaponRefinement,
}) {
  final talentLevels = parseHoyolabTalentLevels(talents);
  return HoyolabSliderSnapshot(
    level: snapToLevelMark(level),
    talentNormal: talentLevels.$1,
    talentSkill: talentLevels.$2,
    talentBurst: talentLevels.$3,
    promoteLevel: promoteLevel.clamp(0, 6),
    constellation: constellation.clamp(0, 6),
    weaponId: weaponId?.isNotEmpty == true ? weaponId : null,
    weaponName: weaponName?.isNotEmpty == true ? weaponName : null,
    weaponLevel:
        weaponLevel == null ? null : snapToLevelMark(weaponLevel),
    weaponRefinement: weaponRefinement?.clamp(1, 5),
  );
}

/// 通常攻撃・元素スキル・元素爆発のレベルへ割り当て
(int, int, int) parseHoyolabTalentLevels(List<HoyolabTalentInput> talents) {
  if (talents.isEmpty) {
    return (1, 1, 1);
  }

  if (talents.length >= 3) {
    return (
      snapTalentLevel(talents[0].level),
      snapTalentLevel(talents[1].level),
      snapTalentLevel(talents[2].level),
    );
  }

  var normal = 1;
  var skill = 1;
  var burst = 1;
  var assigned = 0;

  for (final talent in talents) {
    final level = snapTalentLevel(talent.level);
    final name = talent.name;
    if (_matchesTalentKind(name, _TalentKind.normal)) {
      normal = level;
      assigned++;
    } else if (_matchesTalentKind(name, _TalentKind.burst)) {
      burst = level;
      assigned++;
    } else if (_matchesTalentKind(name, _TalentKind.skill)) {
      skill = level;
      assigned++;
    }
  }

  if (assigned == 0) {
    if (talents.length == 1) {
      return (snapTalentLevel(talents[0].level), 1, 1);
    }
    if (talents.length == 2) {
      return (
        snapTalentLevel(talents[0].level),
        snapTalentLevel(talents[1].level),
        1,
      );
    }
  }

  return (normal, skill, burst);
}

enum _TalentKind { normal, skill, burst }

bool _matchesTalentKind(String name, _TalentKind kind) {
  final lower = name.toLowerCase();
  return switch (kind) {
    _TalentKind.normal =>
      lower.contains('通常') || lower.contains('normal'),
    _TalentKind.skill =>
      lower.contains('元素スキル') ||
          lower.contains('スキル') ||
          lower.contains('skill'),
    _TalentKind.burst =>
      lower.contains('元素爆発') ||
          lower.contains('爆発') ||
          lower.contains('burst'),
  };
}
