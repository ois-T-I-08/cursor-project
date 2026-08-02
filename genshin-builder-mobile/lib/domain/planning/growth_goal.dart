/// User-defined growth goal for a character.
library;

enum GrowthGoalStatus { active, paused, completed }

class GrowthGoal {
  const GrowthGoal({
    required this.id,
    required this.userId,
    required this.characterId,
    this.targetLevel,
    this.targetAscension,
    this.targetTalentNormal,
    this.targetTalentSkill,
    this.targetTalentBurst,
    this.targetWeaponId,
    this.targetWeaponLevel,
    this.priority = 0,
    this.status = GrowthGoalStatus.active,
    this.memo,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  final String id;
  final String userId;
  final String characterId;
  final int? targetLevel;
  final int? targetAscension;
  final int? targetTalentNormal;
  final int? targetTalentSkill;
  final int? targetTalentBurst;
  final String? targetWeaponId;
  final int? targetWeaponLevel;
  final int priority;
  final GrowthGoalStatus status;
  final String? memo;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  bool get hasAnyTarget =>
      targetLevel != null ||
      targetAscension != null ||
      targetTalentNormal != null ||
      targetTalentSkill != null ||
      targetTalentBurst != null ||
      targetWeaponId != null ||
      targetWeaponLevel != null;

  static String? validate(GrowthGoal goal) {
    if (goal.id.isEmpty) return 'Goal id must not be empty';
    if (goal.userId.isEmpty) return 'User id must not be empty';
    if (goal.characterId.isEmpty) return 'Character id must not be empty';
    if (!goal.hasAnyTarget) return 'At least one target must be set';
    if (goal.targetLevel != null) {
      final l = goal.targetLevel!;
      if (l < 1 || l > 90) return 'Target level must be 1-90';
    }
    if (goal.targetAscension != null) {
      final a = goal.targetAscension!;
      if (a < 0 || a > 6) return 'Target ascension must be 0-6';
    }
    for (final t in [
      goal.targetTalentNormal,
      goal.targetTalentSkill,
      goal.targetTalentBurst,
    ]) {
      if (t != null && (t < 1 || t > 10)) return 'Talent target must be 1-10';
    }
    if (goal.targetWeaponLevel != null) {
      final w = goal.targetWeaponLevel!;
      if (w < 1 || w > 90) return 'Weapon level must be 1-90';
    }
    return null;
  }
}
