import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/bookmark_utils.dart';
import '../../../domain/character_stats.dart';
import '../../../domain/level_progression.dart';
import '../../../domain/material_requirements.dart';
import '../../../domain/models/bookmark.dart';
import '../../../domain/models/calculation_models.dart';
import '../../../providers/character_detail_providers.dart';
import '../../shared/material_list_tile.dart';

/// レベル変更に連動する基礎ステータス・突破ステータス・次の段階素材
class CharacterLevelStatsPanel extends ConsumerWidget {
  const CharacterLevelStatsPanel({
    super.key,
    required this.characterId,
    required this.level,
    required this.promotes,
    required this.nextStage,
    required this.resolveName,
    required this.resolveIcon,
    required this.bookmarkContext,
    required this.bookmarks,
    required this.onToggleBookmark,
  });

  final String characterId;
  final int level;
  final List<PromoteStage> promotes;
  final NextStageRequirements? nextStage;
  final String Function(String id) resolveName;
  final String? Function(String id) resolveIcon;
  final CultivationBookmarkContext bookmarkContext;
  final List<MaterialBookmarkEntry> bookmarks;
  final void Function(RequirementLine line, String scope) onToggleBookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(avatarDetailProvider(characterId));
    final theme = Theme.of(context);
    final ascension = getAscensionForLevel(level, promotes);
    final nextAscension = _nextAscensionStage(promotes, ascension);

    return detailAsync.when(
      loading:
          () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
      error:
          (_, __) => Text(
            '基礎ステータスを取得できませんでした',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      data: (detail) {
        final avatarStats = detail?.stats;
        if (avatarStats == null) {
          return Text(
            '基礎ステータスを取得できませんでした',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );
        }

        final base = computeCharacterBaseStats(
          avatarStats: avatarStats,
          level: level,
          ascension: ascension,
        );
        final currentPromote = findPromoteByLevel(
          avatarStats.promotes,
          ascension,
        );
        final prevPromote = findPromoteByLevel(
          avatarStats.promotes,
          ascension - 1,
        );
        final nextPromote =
            nextAscension == null
                ? null
                : findPromoteByLevel(
                  avatarStats.promotes,
                  nextAscension.promoteLevel,
                );

        final beforeBonuses = ascensionBonusProps(prevPromote);
        final afterBonuses = ascensionBonusProps(currentPromote);
        final stageLabel = formatAscensionStageLabel(
          promoteLevel: ascension,
          promotes: avatarStats.promotes,
        );

        final nextLines =
            nextStage == null
                ? const <RequirementLine>[]
                : nextStageToRequirementLines(
                  nextStage!.materials,
                  nextStage!.levelUpMaterials,
                  nextStage!.mora,
                  resolveName,
                  resolveIcon: resolveIcon,
                );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('基礎ステータス', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'レベル変更に連動して更新されます（シミュレーション）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _statGrid(theme, [
              ('基礎HP', base.hp.round().toString()),
              ('基礎攻撃力', base.atk.round().toString()),
              ('基礎防御力', base.def.round().toString()),
            ]),
            const Divider(height: 28),
            Text('突破ステータス', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _kv(theme, '現在突破段階', stageLabel),
            const SizedBox(height: 8),
            Text('突破前ステータス', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            _bonusList(theme, beforeBonuses, emptyLabel: 'なし（未突破）'),
            const SizedBox(height: 10),
            Text('突破後ステータス（現在）', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            _bonusList(theme, afterBonuses, emptyLabel: '突破ボーナスなし'),
            if (nextPromote != null && nextAscension != null) ...[
              const SizedBox(height: 10),
              Text(
                '次の突破後（最大Lv${nextAscension.unlockMaxLevel}）',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              _bonusList(
                theme,
                ascensionBonusProps(nextPromote),
                emptyLabel: '—',
              ),
            ],
            const Divider(height: 28),
            Text('次の段階', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            if (nextStage == null)
              Text('最大レベルです', style: theme.textTheme.bodyMedium)
            else ...[
              Text(
                'Lv${nextStage!.fromLevel}→Lv${nextStage!.toLevel}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...nextLines.map((line) {
                final sourceKey = makeItemSourceKey(
                  bookmarkContext,
                  'next',
                  line.materialId,
                );
                final bookmarked = bookmarks.any(
                  (b) =>
                      b.sourceKey == sourceKey &&
                      b.materialId == line.materialId,
                );
                return MaterialListTile(
                  line: line,
                  isBookmarked: bookmarked,
                  onToggleBookmark: () => onToggleBookmark(line, 'next'),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  PromoteStage? _nextAscensionStage(
    List<PromoteStage> promotes,
    int currentPromote,
  ) {
    final sorted = [...promotes]
      ..sort((a, b) => a.promoteLevel.compareTo(b.promoteLevel));
    for (final p in sorted) {
      if (p.promoteLevel > currentPromote && p.promoteLevel > 0) {
        return p;
      }
    }
    return null;
  }

  Widget _statGrid(ThemeData theme, List<(String, String)> items) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          items
              .map(
                (item) => SizedBox(
                  width: 110,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.$2,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
    );
  }

  Widget _bonusList(
    ThemeData theme,
    Map<String, double> bonuses, {
    required String emptyLabel,
  }) {
    if (bonuses.isEmpty) {
      return Text(
        emptyLabel,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      children:
          bonuses.entries.map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      fightPropLabel(e.key),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    '+${formatFightPropValue(e.key, e.value)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  Widget _kv(ThemeData theme, String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
