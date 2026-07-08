import 'package:flutter/material.dart';

import '../../../domain/bookmark_utils.dart';
import '../../../domain/level_config.dart';
import '../../../domain/material_requirements.dart';
import '../../../domain/models/bookmark.dart';
import '../../../domain/models/calculation_models.dart';
import '../../../domain/talent_progression.dart';
import '../../shared/mark_slider.dart';
import '../../shared/material_list_tile.dart';
import '../../shared/max_enhanced_banner.dart';

class TalentMaterialsSection extends StatelessWidget {
  const TalentMaterialsSection({
    super.key,
    required this.characterId,
    required this.characterName,
    required this.characterIconUrl,
    required this.talentKind,
    required this.talentKey,
    required this.label,
    required this.currentLevel,
    required this.upgrades,
    required this.bookmarks,
    required this.resolveName,
    required this.resolveIcon,
    required this.onLevelChanged,
    required this.onToggleBookmark,
    required this.onBookmarkRange,
    required this.onToggleRangeLineBookmark,
  });

  final String characterId;
  final String characterName;
  final String characterIconUrl;
  final String talentKind;
  final String talentKey;
  final String label;
  final int currentLevel;
  final List<TalentLevelUpgrade> upgrades;
  final List<MaterialBookmarkEntry> bookmarks;
  final String Function(String id) resolveName;
  final String? Function(String id) resolveIcon;
  final ValueChanged<int> onLevelChanged;
  final Future<void> Function(
    CultivationBookmarkContext ctx,
    RequirementLine line,
    String scope,
  ) onToggleBookmark;
  final Future<void> Function(
    CultivationBookmarkContext ctx,
    List<RequirementLine> lines,
    String sourceKey,
  ) onBookmarkRange;
  final Future<void> Function(
    CultivationBookmarkContext ctx,
    RequirementLine line,
    String rangeSourceKey,
  ) onToggleRangeLineBookmark;

  CultivationBookmarkContext get _ctx => CultivationBookmarkContext(
        kind: CultivationKind.talent,
        targetId: '$characterId:$talentKind',
        targetName: characterName,
        subLabel: label,
        character: BookmarkCharacterSource(
          characterId: characterId,
          characterName: characterName,
          characterIconUrl: characterIconUrl,
        ),
      );

  bool _isBookmarked(String sourceKey, String materialId) =>
      isMaterialBookmarked(bookmarks, sourceKey, materialId);

  @override
  Widget build(BuildContext context) {
    if (upgrades.isEmpty) return const SizedBox.shrink();

    final next = getNextTalentRequirements(
      currentLevel,
      talentLevelMax,
      upgrades,
    );
    final rangeLines = getRangeTalentRequirements(
      currentLevel,
      talentLevelMax,
      talentLevelMax,
      upgrades,
      resolveName: resolveName,
      resolveIcon: resolveIcon,
    );
    final rangeSourceKey =
        makeRangeSourceKey(_ctx, currentLevel, talentLevelMax);

    final isMaxEnhanced = currentLevel >= talentLevelMax;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMaxEnhanced) ...[
          MaxEnhancedBanner(label: label, level: currentLevel),
        ] else ...[
          Row(
            children: [
              Expanded(
                child:
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
              ),
              if (rangeLines.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.bookmark_add_outlined),
                  tooltip: '$label を目標までブックマーク',
                  onPressed: () =>
                      onBookmarkRange(_ctx, rangeLines, rangeSourceKey),
                ),
            ],
          ),
          MarkSlider(
            label: '$labelレベル',
            value: currentLevel,
            marks: talentMarks,
            max: talentLevelMax,
            onChanged: onLevelChanged,
          ),
          if (next != null) ...[
            Text('次の段階', style: Theme.of(context).textTheme.labelLarge),
            ...nextStageToRequirementLines(
              next.materials,
              const [],
              next.mora,
              resolveName,
              resolveIcon: resolveIcon,
            ).map((line) {
              final sourceKey =
                  makeItemSourceKey(_ctx, 'next', line.materialId);
              return MaterialListTile(
                line: line,
                isBookmarked: _isBookmarked(sourceKey, line.materialId),
                onToggleBookmark: () => onToggleBookmark(_ctx, line, 'next'),
              );
            }),
          ],
          if (rangeLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('最大までの合計', style: Theme.of(context).textTheme.labelLarge),
            ...rangeLines.map(
              (line) => MaterialListTile(
                line: line,
                isBookmarked: _isBookmarked(rangeSourceKey, line.materialId),
                onToggleBookmark: () =>
                    onToggleRangeLineBookmark(_ctx, line, rangeSourceKey),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
