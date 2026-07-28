import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/artifacts/character_recommended_artifact_sets.dart';
import '../../../domain/build_recommendations/build_recommendation.dart';
import '../../../domain/models/amber_detail_models.dart';
import '../../../providers/artifact_sets_page_providers.dart';
import '../../../providers/build_recommendation_providers.dart';
import '../../../providers/character_detail_providers.dart';
import '../../shared/game_icon_image.dart';
import 'guide_main_stats_panel.dart';
import 'guide_section_state.dart';
import 'guide_source_label.dart';

/// おすすめ聖遺物: Akasha 使用率と YouTube おすすめを別グループで表示。
class CharacterArtifactInsightsSection extends ConsumerWidget {
  const CharacterArtifactInsightsSection({
    super.key,
    required this.characterId,
  });

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final akashaAsync =
        ref.watch(characterRecommendedArtifactSetsProvider(characterId));
    final guideAsync = ref.watch(buildRecommendationProvider(characterId));
    final setsAsync = ref.watch(artifactSetsProvider);

    return CharacterArtifactInsightsView(
      akashaAsync: akashaAsync,
      guideAsync: guideAsync,
      artifactSets: setsAsync.valueOrNull ?? const [],
      onRetryAkasha: () => ref.invalidate(
        characterRecommendedArtifactSetsProvider(characterId),
      ),
      onRetryGuide: () =>
          ref.invalidate(buildRecommendationProvider(characterId)),
    );
  }
}

/// Provider 非依存の表示本体（Widget テスト用）
class CharacterArtifactInsightsView extends StatelessWidget {
  const CharacterArtifactInsightsView({
    super.key,
    required this.akashaAsync,
    required this.guideAsync,
    this.artifactSets = const [],
    this.onRetryAkasha,
    this.onRetryGuide,
  });

  final AsyncValue<List<CharacterRecommendedArtifactSet>> akashaAsync;
  final AsyncValue<CharacterBuildRecommendation?> guideAsync;
  final List<ArtifactSetDetail> artifactSets;
  final VoidCallback? onRetryAkasha;
  final VoidCallback? onRetryGuide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('おすすめ聖遺物', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '使用率（実績）と攻略おすすめは別の情報です。順位と使用率を同じ意味では扱いません。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text('使用率', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          const GuideSourceLabel(source: GuideInsightSource.akasha),
          const SizedBox(height: 8),
          akashaAsync.when(
            loading: () => const GuideSectionLoading(),
            error: (_, __) => GuideSectionMessage(
              message: '使用率データを取得できませんでした。',
              onRetry: onRetryAkasha,
            ),
            data: (items) {
              final akasha = items.where((e) => e.isFromAkasha).toList();
              final fallback = items.where((e) => !e.isFromAkasha).toList();
              final show = akasha.isNotEmpty ? akasha : fallback;
              if (show.isEmpty) {
                return const GuideSectionMessage(message: '使用率データがありません。');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (akasha.isEmpty && fallback.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Akasha 使用率が不足しているため、設定フォールバックを表示しています。',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ...show.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _AkashaSetTile(item: item, rank: index + 1),
                    );
                  }),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Text('攻略おすすめ', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          const GuideSourceLabel(source: GuideInsightSource.youtube),
          const SizedBox(height: 8),
          guideAsync.when(
            loading: () => const GuideSectionLoading(),
            error: (error, _) {
              if (error is BuildRecommendationException &&
                  (error.failure == BuildRecommendationFailure.notConfigured ||
                      error.failure == BuildRecommendationFailure.notFound)) {
                return const GuideSectionMessage(
                  message: 'おすすめ情報はまだ登録されていません。',
                );
              }
              return GuideSectionMessage(
                message: '攻略おすすめを取得できませんでした。',
                onRetry: onRetryGuide,
              );
            },
            data: (rec) {
              if (rec == null) {
                return const GuideSectionMessage(
                  message: 'おすすめ情報はまだ登録されていません。',
                );
              }
              final youtubeSets = rec.artifactRecommendations;
              final hasMain = rec.mainStats.isNotEmpty;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rec.freshnessCaption != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        rec.freshnessCaption!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (youtubeSets.isEmpty)
                    const GuideSectionMessage(
                      message: '攻略動画のおすすめ聖遺物セットはまだ登録されていません。',
                    )
                  else
                    ...youtubeSets.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _YoutubeArtifactTile(
                          item: item,
                          catalog: artifactSets,
                        ),
                      ),
                    ),
                  if (hasMain) ...[
                    const SizedBox(height: 8),
                    GuideMainStatsPanel(
                      mainStats: rec.mainStats,
                      freshnessCaption: null,
                      compact: false,
                    ),
                  ] else
                    const GuideSectionMessage(
                      message: 'メインステータスのおすすめはまだ登録されていません。',
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AkashaSetTile extends StatelessWidget {
  const _AkashaSetTile({
    required this.item,
    required this.rank,
  });

  final CharacterRecommendedArtifactSet item;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final set = item.set;
    final rateLabel = item.usageRate == null
        ? 'データなし'
        : '${(item.usageRate! * 100).round()}%';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            GameIconImage(
              iconUrl: set.iconUrl,
              size: 44,
              borderRadius: 8,
              fallback: Text(
                set.name.isNotEmpty ? set.name[0] : '?',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    set.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    item.usageRate == null
                        ? '使用率 $rateLabel · ${item.isFromAkasha ? '$rank位' : 'フォールバック'}'
                        : '使用率 $rateLabel · $rank位',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YoutubeArtifactTile extends StatelessWidget {
  const _YoutubeArtifactTile({
    required this.item,
    required this.catalog,
  });

  final GuideArtifactRecommendation item;
  final List<ArtifactSetDetail> catalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byId = {for (final s in catalog) s.id: s};
    final labels = <String>[];
    String? iconUrl;
    for (final part in item.sets) {
      final set = byId[part.setId];
      if (set != null) {
        labels.add('${set.name} ${part.pieces}セット');
        iconUrl ??= set.iconUrl;
      } else {
        labels.add('未登録セット(${part.setId}) ${part.pieces}セット');
      }
    }
    final title = labels.join(' ＋ ');
    final meta = <String>[
      if (item.rank != null) 'おすすめ ${item.rank}位',
      if (item.recommendationLevel != null) item.recommendationLevel!.label,
      if (item.isAlternative) '代替候補',
      if (item.role != null && item.role!.trim().isNotEmpty) item.role!,
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GameIconImage(
              iconUrl: iconUrl,
              size: 44,
              borderRadius: 8,
              fallback: Text(
                title.isNotEmpty ? title[0] : '?',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (meta.isNotEmpty)
                    Text(
                      meta.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (item.reason != null && item.reason!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        item.reason!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (item.conditions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '条件: ${item.conditions.join(' / ')}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (item.citation?.caption != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '出典: ${item.citation!.caption}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
