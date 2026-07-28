import 'package:flutter/material.dart';

import '../../../domain/artifact_score_weights.dart';
import '../../../domain/models/master_models.dart';
import '../../../domain/artifact_score.dart';
import '../../../domain/level_config.dart';
import '../../../domain/models/artifact_state.dart';
import '../../../domain/models/bookmark.dart';
import '../../../domain/models/calculation_models.dart';
import '../../../domain/models/character_build_snapshot.dart';
import '../../hoyolab/widgets/hoyolab_character_status_card.dart';
import '../../shared/mark_slider.dart';
import '../../shared/material_list_tile.dart';
import '../../shared/max_enhanced_banner.dart';
import 'artifact_completion_panel.dart';
import 'artifact_score_summary_card.dart';
import 'character_detail_bookmark_actions.dart';
import 'character_level_stats_panel.dart';
import 'character_artifact_insights_section.dart';
import 'character_relics_section.dart';
import 'character_talent_sections_list.dart';
import 'character_weapon_insights_section.dart';
import 'simulated_stats_section.dart';
import 'skill_details_section.dart';
import 'weapon_detail_sheet.dart';
import 'weapon_materials_section.dart';

/// Builds the six [TabBarView] children for [CharacterDetailScreen].
///
/// Owns no state — all values and callbacks come from the screen.
class CharacterDetailTabViews {
  CharacterDetailTabViews({
    required this.characterId,
    required this.character,
    required this.hoyolabSynced,
    required this.level,
    required this.targetLevel,
    required this.talentNormal,
    required this.talentSkill,
    required this.talentBurst,
    required this.weaponId,
    required this.weaponLevel,
    required this.targetWeaponLevel,
    required this.weaponRarity,
    required this.weaponRefinement,
    required this.artifacts,
    required this.promotes,
    required this.weaponPromotes,
    required this.talents,
    required this.weapons,
    required this.bookmarks,
    required this.fetchedSnapshot,
    required this.artifactScoreType,
    required this.resolvedArtifactScoreType,
    required this.artifactScoreWeights,
    required this.artifactScoreTypeUserSet,
    required this.artifactCompleted,
    required this.bookmarkCtx,
    required this.weaponBookmarkCtx,
    required this.rangeLines,
    required this.rangeSourceKey,
    required this.nextStage,
    required this.bookmarkActions,
    required this.resolveName,
    required this.resolveIcon,
    required this.isBookmarked,
    required this.onLevelChanged,
    required this.onTargetLevelChanged,
    required this.onTalentNormalChanged,
    required this.onTalentSkillChanged,
    required this.onTalentBurstChanged,
    required this.onWeaponSelected,
    required this.onWeaponLevelChanged,
    required this.onTargetWeaponLevelChanged,
    required this.onArtifactsChanged,
    required this.onArtifactScoreTypeChanged,
    required this.onArtifactCompletedChanged,
    required this.onResetToFetched,
    required this.snapshotFromCurrent,
  });

  final String characterId;
  final MasterCharacter character;
  final bool hoyolabSynced;
  final int level;
  final int targetLevel;
  final int talentNormal;
  final int talentSkill;
  final int talentBurst;
  final String weaponId;
  final int weaponLevel;
  final int targetWeaponLevel;
  final int weaponRarity;
  final int weaponRefinement;
  final ArtifactState artifacts;
  final List<PromoteStage> promotes;
  final List<PromoteStage> weaponPromotes;
  final Map<String, List<TalentLevelUpgrade>> talents;
  final List<MasterWeapon> weapons;
  final List<MaterialBookmarkEntry> bookmarks;
  final CharacterBuildSnapshot? fetchedSnapshot;
  final ArtifactScoreType artifactScoreType;
  final ArtifactScoreType resolvedArtifactScoreType;
  final ArtifactStatWeights artifactScoreWeights;
  final bool artifactScoreTypeUserSet;
  final bool artifactCompleted;
  final CultivationBookmarkContext bookmarkCtx;
  final CultivationBookmarkContext weaponBookmarkCtx;
  final List<RequirementLine> rangeLines;
  final String rangeSourceKey;
  final NextStageRequirements? nextStage;
  final CharacterDetailBookmarkActions bookmarkActions;
  final String Function(String id) resolveName;
  final String? Function(String id) resolveIcon;
  final bool Function(String sourceKey, String materialId) isBookmarked;
  final ValueChanged<int> onLevelChanged;
  final ValueChanged<int> onTargetLevelChanged;
  final ValueChanged<int> onTalentNormalChanged;
  final ValueChanged<int> onTalentSkillChanged;
  final ValueChanged<int> onTalentBurstChanged;
  final Future<void> Function(String? weaponId) onWeaponSelected;
  final ValueChanged<int> onWeaponLevelChanged;
  final ValueChanged<int> onTargetWeaponLevelChanged;
  final ValueChanged<ArtifactState> onArtifactsChanged;
  final ValueChanged<ArtifactScoreType> onArtifactScoreTypeChanged;
  final ValueChanged<bool> onArtifactCompletedChanged;
  final VoidCallback onResetToFetched;
  final CharacterBuildSnapshot Function() snapshotFromCurrent;

  List<Widget> buildTabs(BuildContext context) => [
    _buildLevelTab(context),
    _buildWeaponTab(context),
    _buildRelicsTab(),
    _buildTalentTab(context),
    _buildSimulationTab(context),
    _buildHoyolabTab(),
  ];

  Widget _buildLevelTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hoyolabSynced) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              avatar: Icon(
                Icons.sync,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: const Text('HoYoLAB のレベルを反映済み'),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (level >= levelMax) ...[
          MaxEnhancedBanner(label: 'キャラクターレベル', level: level),
          const SizedBox(height: 8),
        ],
        LevelMarkSlider(
          label: level >= levelMax ? '現在レベル（シミュレーション）' : '現在レベル',
          value: level,
          onChanged: onLevelChanged,
        ),
        const SizedBox(height: 16),
        CharacterLevelStatsPanel(
          characterId: character.id,
          level: level,
          promotes: promotes,
          nextStage: nextStage,
          resolveName: resolveName,
          resolveIcon: resolveIcon,
          bookmarkContext: bookmarkCtx,
          bookmarks: bookmarks,
          onToggleBookmark:
              (line, scope) =>
                  bookmarkActions.toggleLineBookmark(bookmarkCtx, line, scope),
        ),
        const Divider(height: 32),
        LevelMarkSlider(
          label: '目標レベル',
          value: targetLevel,
          onChanged: onTargetLevelChanged,
          headerTrailing: IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: '範囲をブックマーク',
            onPressed:
                () => bookmarkActions.bookmarkRange(
                  bookmarkCtx,
                  rangeLines,
                  rangeSourceKey,
                ),
          ),
        ),
        const Divider(height: 24),
        Text('目標までの合計', style: Theme.of(context).textTheme.titleMedium),
        ...rangeLines.map(
          (line) => MaterialListTile(
            line: line,
            isBookmarked: isBookmarked(rangeSourceKey, line.materialId),
            onToggleBookmark:
                () => bookmarkActions.toggleRangeLineBookmark(
                  bookmarkCtx,
                  line,
                  rangeSourceKey,
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeaponTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CharacterWeaponInsightsSection(
          characterId: characterId,
          weapons: weapons,
        ),
        const SizedBox(height: 24),
        WeaponMaterialsSection(
          showTitle: true,
          weapons: weapons,
          allowedWeaponType: character.weaponType,
          character: character,
          selectedWeaponId: weaponId,
          weaponLevel: weaponLevel,
          targetWeaponLevel: targetWeaponLevel,
          promotes: weaponPromotes,
          weaponRarity: weaponRarity,
          equippedRefinement: weaponRefinement,
          bookmarkContext: weaponBookmarkCtx,
          bookmarks: bookmarks,
          resolveName: resolveName,
          resolveIcon: resolveIcon,
          onWeaponSelected: onWeaponSelected,
          onWeaponLevelChanged: onWeaponLevelChanged,
          onTargetWeaponLevelChanged: onTargetWeaponLevelChanged,
          onShowWeaponDetail: (weapon, {required isEquipped}) {
            showWeaponDetailSheet(
              context: context,
              weaponId: weapon.id,
              weaponLevel: isEquipped ? weaponLevel : levelMax,
              refinement: isEquipped ? weaponRefinement : 1,
            );
          },
          onToggleBookmark:
              (line, scope) => bookmarkActions.toggleLineBookmark(
                weaponBookmarkCtx,
                line,
                scope,
              ),
          onToggleRangeBookmark:
              (line, rangeSourceKey) => bookmarkActions.toggleRangeLineBookmark(
                weaponBookmarkCtx,
                line,
                rangeSourceKey,
              ),
          onBookmarkRange:
              (lines, sourceKey) => bookmarkActions.bookmarkRange(
                weaponBookmarkCtx,
                lines,
                sourceKey,
              ),
        ),
      ],
    );
  }

  Widget _buildRelicsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ArtifactCompletionPanel(
          artifacts: artifacts,
          scoreType: artifactScoreType,
          weights: artifactScoreWeights,
          completed: artifactCompleted,
          onCompletedChanged: onArtifactCompletedChanged,
        ),
        const SizedBox(height: 16),
        // 旧「スコア基準」の位置に 5部位スコア合計を表示（基準はセクション最下部へ移動）
        ArtifactScoreSummaryCard(
          artifacts: artifacts,
          scoreType: artifactScoreType,
          weights: artifactScoreWeights,
          scoreTypeLabel: formatArtifactScoreTypeLabel(
            scoreType: artifactScoreType,
            resolvedScoreType: resolvedArtifactScoreType,
            scoreTypeUserSet: artifactScoreTypeUserSet,
          ),
        ),
        const SizedBox(height: 16),
        CharacterArtifactInsightsSection(characterId: characterId),
        CharacterRelicsSection(
          characterId: characterId,
          artifacts: artifacts,
          scoreType: artifactScoreType,
          resolvedScoreType: resolvedArtifactScoreType,
          scoreTypeUserSet: artifactScoreTypeUserSet,
          weights: artifactScoreWeights,
          onScoreTypeChanged: onArtifactScoreTypeChanged,
          onChanged: onArtifactsChanged,
        ),
      ],
    );
  }

  Widget _buildTalentTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SkillDetailsSection(
          characterId: character.id,
          talentNormal: talentNormal,
          talentSkill: talentSkill,
          talentBurst: talentBurst,
        ),
        const Divider(height: 32),
        Text('育成素材', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        CharacterTalentSectionsList(
          character: character,
          talents: talents,
          talentNormal: talentNormal,
          talentSkill: talentSkill,
          talentBurst: talentBurst,
          bookmarks: bookmarks,
          resolveName: resolveName,
          resolveIcon: resolveIcon,
          onTalentNormalChanged: onTalentNormalChanged,
          onTalentSkillChanged: onTalentSkillChanged,
          onTalentBurstChanged: onTalentBurstChanged,
          onToggleBookmark: bookmarkActions.toggleLineBookmark,
          onBookmarkRange: bookmarkActions.bookmarkRange,
          onToggleRangeLineBookmark: bookmarkActions.toggleRangeLineBookmark,
        ),
      ],
    );
  }

  Widget _buildSimulationTab(BuildContext context) {
    final baseline = fetchedSnapshot;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'ステータス',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: baseline == null ? null : onResetToFetched,
              icon: const Icon(Icons.settings_backup_restore, size: 18),
              label: const Text('取得情報に戻す'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (baseline == null)
          const Text('取得情報がまだありません。')
        else
          SimulatedStatsSection(
            character: character,
            promotes: promotes,
            baseline: baseline,
            simulated: snapshotFromCurrent(),
          ),
      ],
    );
  }

  Widget _buildHoyolabTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [HoyolabCharacterStatusCard(characterId: characterId)],
    );
  }
}
