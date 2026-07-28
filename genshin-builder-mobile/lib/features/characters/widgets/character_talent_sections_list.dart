import 'package:flutter/material.dart';

import '../../../domain/models/master_models.dart';
import '../../../domain/models/bookmark.dart';
import '../../../domain/models/calculation_models.dart';
import 'talent_materials_section.dart';

enum CharacterTalentSlot { normal, skill, burst }

/// キャラ詳細の天賦セクション一覧
class CharacterTalentSectionsList extends StatelessWidget {
  const CharacterTalentSectionsList({
    super.key,
    required this.character,
    required this.talents,
    required this.talentNormal,
    required this.talentSkill,
    required this.talentBurst,
    required this.bookmarks,
    required this.resolveName,
    required this.resolveIcon,
    required this.onTalentNormalChanged,
    required this.onTalentSkillChanged,
    required this.onTalentBurstChanged,
    required this.onToggleBookmark,
    required this.onBookmarkRange,
    required this.onToggleRangeLineBookmark,
  });

  final MasterCharacter character;
  final Map<String, List<TalentLevelUpgrade>> talents;
  final int talentNormal;
  final int talentSkill;
  final int talentBurst;
  final List<MaterialBookmarkEntry> bookmarks;
  final String Function(String id) resolveName;
  final String? Function(String id) resolveIcon;
  final ValueChanged<int> onTalentNormalChanged;
  final ValueChanged<int> onTalentSkillChanged;
  final ValueChanged<int> onTalentBurstChanged;
  final Future<void> Function(
    CultivationBookmarkContext ctx,
    RequirementLine line,
    String scope,
  )
  onToggleBookmark;
  final Future<void> Function(
    CultivationBookmarkContext ctx,
    List<RequirementLine> lines,
    String sourceKey,
  )
  onBookmarkRange;
  final Future<void> Function(
    CultivationBookmarkContext ctx,
    RequirementLine line,
    String rangeSourceKey,
  )
  onToggleRangeLineBookmark;

  static const _slots = [
    ('normal', 'skill_0', '通常攻撃', CharacterTalentSlot.normal),
    ('skill', 'skill_1', '元素スキル', CharacterTalentSlot.skill),
    ('burst', 'skill_2', '元素爆発', CharacterTalentSlot.burst),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          _slots.map((slot) {
            final upgrades = talents[slot.$2] ?? [];
            if (upgrades.isEmpty) return const SizedBox.shrink();
            final level = switch (slot.$4) {
              CharacterTalentSlot.normal => talentNormal,
              CharacterTalentSlot.skill => talentSkill,
              CharacterTalentSlot.burst => talentBurst,
            };
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: TalentMaterialsSection(
                characterId: character.id,
                characterName: character.name,
                characterIconUrl: character.iconUrl,
                talentKind: slot.$1,
                talentKey: slot.$2,
                label: slot.$3,
                currentLevel: level,
                upgrades: upgrades,
                bookmarks: bookmarks,
                resolveName: resolveName,
                resolveIcon: resolveIcon,
                onLevelChanged: switch (slot.$4) {
                  CharacterTalentSlot.normal => onTalentNormalChanged,
                  CharacterTalentSlot.skill => onTalentSkillChanged,
                  CharacterTalentSlot.burst => onTalentBurstChanged,
                },
                onToggleBookmark: onToggleBookmark,
                onBookmarkRange: onBookmarkRange,
                onToggleRangeLineBookmark: onToggleRangeLineBookmark,
              ),
            );
          }).toList(),
    );
  }
}
