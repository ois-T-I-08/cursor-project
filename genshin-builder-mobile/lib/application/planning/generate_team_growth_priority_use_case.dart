import '../../domain/planning/upgrade_option.dart';
import '../../domain/planning/team_growth_priority.dart';
import '../../domain/team/team_models.dart';
import '../../domain/account/account_snapshot.dart';
import '../../domain/recommendation/recommendation.dart';

/// Generates team growth priority for a saved team.
///
/// Evaluates each member based on:
/// - Current level / talent / weapon state
/// - Existence of UpgradeOptions
/// - Impact scores
class GenerateTeamGrowthPriorityUseCase {
  const GenerateTeamGrowthPriorityUseCase();

  static const ruleVersion = '1';

  TeamGrowthPriorityReport call({
    required Team team,
    required AccountSnapshot snapshot,
    required Map<String, List<UpgradeOption>> upgradeOptionsByCharacter,
    DateTime? generatedAt,
  }) {
    final priorities = <TeamMemberGrowthPriority>[];
    final names = {
      for (final c in snapshot.characters) c.characterId: c.name,
    };

    for (final member in team.members) {
      final char = _resolveCharacter(member.characterId, snapshot.characters);
      final displayName = _resolveCharacterName(member.characterId, names) ??
          char?.name.trim() ??
          '';

      if (char == null || !char.isOwned) {
        priorities.add(TeamMemberGrowthPriority(
          characterId: member.characterId,
          characterName: displayName,
          priority: -1,
          reasons: ['未所持、またはキャラが見つかりません'],
          confidence: RecommendationConfidence.unknown,
        ));
        continue;
      }

      final options = upgradeOptionsByCharacter[member.characterId] ??
          upgradeOptionsByCharacter[char.characterId] ??
          [];
      final reasons = <String>[];
      double totalScore = 0;

      if (options.isNotEmpty) {
        for (final opt in options) {
          totalScore += opt.impact?.impactScore ?? 0;
        }
        reasons.add('強化候補が ${options.length} 件あります');
      }

      if (char.level < 80) {
        reasons.add('キャラレベル（${char.level}）が 80 未満です');
        totalScore += 0.1;
      }
      if (char.weaponLevel < 80) {
        reasons.add('武器レベル（${char.weaponLevel}）が 80 未満です');
        totalScore += 0.08;
      }
      final maxTalent = [char.talentNormal, char.talentSkill, char.talentBurst]
          .reduce((a, b) => a > b ? a : b);
      if (maxTalent < 6) {
        reasons.add('最高天賦（Lv.$maxTalent）が 6 未満です');
        totalScore += 0.05;
      }

      final priority = totalScore > 0.3
          ? 3
          : totalScore > 0.15
              ? 2
              : totalScore > 0
                  ? 1
                  : 0;

      priorities.add(TeamMemberGrowthPriority(
        characterId: member.characterId,
        characterName: displayName.isNotEmpty ? displayName : char.name,
        priority: priority,
        score: totalScore,
        upgradeOptions: options.take(3).toList(),
        reasons: reasons,
        confidence: options.isNotEmpty
            ? RecommendationConfidence.medium
            : RecommendationConfidence.low,
      ));
    }

    // Sort by priority desc, then score desc
    priorities.sort((a, b) {
      final cmp = b.priority.compareTo(a.priority);
      if (cmp != 0) return cmp;
      return b.score.compareTo(a.score);
    });

    final nameById = {
      for (final p in priorities) p.characterId: p.displayName,
    };

    // Shared material opportunities
    final allMaterials = <String, Set<String>>{};
    for (final p in priorities) {
      for (final opt in p.upgradeOptions) {
        for (final matId in opt.materialsCost.keys) {
          allMaterials.putIfAbsent(matId, () => {});
          allMaterials[matId]!.add(p.characterId);
        }
      }
    }
    final shared = allMaterials.entries
        .where((e) => e.value.length > 1)
        .map((e) {
          final charNames =
              e.value.map((id) => nameById[id] ?? id).join('、');
          return '素材 ${e.key} を $charNames が共有';
        })
        .toList();

    return TeamGrowthPriorityReport(
      teamId: team.id,
      teamName: team.name,
      memberPriorities: priorities,
      sharedMaterialOpportunities: shared,
      confidence: priorities.any((p) => p.score > 0)
          ? RecommendationConfidence.medium
          : RecommendationConfidence.low,
      completeness: DataCompleteness.partial,
      missingData: snapshot.missingData,
      generatedAt: generatedAt ?? DateTime.now(),
    );
  }

  CharacterSnapshot? _resolveCharacter(
    String characterId,
    List<CharacterSnapshot> characters,
  ) {
    for (final c in characters) {
      if (c.characterId == characterId) return c;
    }
    final base = characterId.split('-').first;
    for (final c in characters) {
      if (c.characterId == base || c.characterId.startsWith('$base-')) {
        return c;
      }
    }
    return null;
  }

  String? _resolveCharacterName(
    String characterId,
    Map<String, String> names,
  ) {
    final direct = names[characterId];
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();

    final base = characterId.split('-').first;
    final byBase = names[base];
    if (byBase != null && byBase.trim().isNotEmpty) return byBase.trim();

    for (final e in names.entries) {
      if (e.key == base || e.key.startsWith('$base-')) {
        final n = e.value.trim();
        if (n.isNotEmpty) return n;
      }
    }
    return null;
  }
}
