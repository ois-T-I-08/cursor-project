import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/build_recommendations/build_recommendation.dart';
import '../../../domain/character_stats.dart';
import '../../../providers/build_recommendation_providers.dart';
import 'guide_source_label.dart';

/// YouTube 由来の目標ステータス目安カード。公式/理想/最適の断定はしない。
class RecommendedStatsCard extends ConsumerWidget {
  const RecommendedStatsCard({
    super.key,
    required this.characterId,
    required this.currentStats,
  });

  final String characterId;
  final StatValues currentStats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(buildRecommendationProvider(characterId));
    return async.when(
      loading:
          () => const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(minHeight: 2),
          ),
      error: (error, _) {
        if (error is BuildRecommendationException &&
            (error.failure == BuildRecommendationFailure.notConfigured ||
                error.failure == BuildRecommendationFailure.notFound)) {
          return const SizedBox.shrink();
        }
        return Card(
          margin: const EdgeInsets.only(top: 16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '動画内推奨目安を取得できませんでした。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed:
                      () => ref.invalidate(
                        buildRecommendationProvider(characterId),
                      ),
                  child: const Text('再試行'),
                ),
              ],
            ),
          ),
        );
      },
      data: (recommendation) {
        if (recommendation == null) return const SizedBox.shrink();
        return _RecommendationBody(
          recommendation: recommendation,
          currentStats: currentStats,
          onRetry:
              () => ref.invalidate(buildRecommendationProvider(characterId)),
        );
      },
    );
  }
}

class _RecommendationBody extends StatelessWidget {
  const _RecommendationBody({
    required this.recommendation,
    required this.currentStats,
    required this.onRetry,
  });

  final CharacterBuildRecommendation recommendation;
  final StatValues currentStats;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    recommendation.label,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: '再読込',
                ),
              ],
            ),
            const GuideSourceLabel(source: GuideInsightSource.youtube),
            const SizedBox(height: 4),
            Text(
              '攻略動画の画面内で確認された目安です。公式推奨や最適値ではありません。'
              '条件付き効果・編成バフは含みません。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (recommendation.freshnessCaption != null) ...[
              const SizedBox(height: 4),
              Text(
                recommendation.freshnessCaption!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (recommendation.targets.isEmpty)
              Text(
                '目標ステータス情報がありません。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...recommendation.targets.map((target) {
                final current = currentStats[target.stat] ?? 0;
                final displayCurrent =
                    percentStatKeys.contains(target.stat)
                        ? current * 100
                        : current;
                final verdict = compareStatToTarget(
                  current: displayCurrent,
                  target: target,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${statLabels[target.stat] ?? target.stat.name}'
                          '${_rangeLabel(target)}',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _verdictLabel(verdict),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: _verdictColor(theme, verdict),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 8),
            Text('根拠動画', style: theme.textTheme.labelMedium),
            ...recommendation.sources.map((source) {
              final canOpen = isSafeYoutubeGuideUrl(source.sourceUrl);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  source.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${source.channelTitle}'
                  '${recommendation.lastVerifiedAt != null ? ' · 確認 ${recommendation.lastVerifiedAt!.toLocal().toIso8601String().split('T').first}' : ''}'
                  ' · 管理者確認済み',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing:
                    canOpen ? const Icon(Icons.open_in_new, size: 18) : null,
                onTap: canOpen ? () => _openUrl(source.sourceUrl) : null,
              );
            }),
            if (recommendation.evidence.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('動画内で確認', style: theme.textTheme.labelMedium),
              ...recommendation.evidence.take(3).map((e) {
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: InkWell(
                    onTap: () {
                      BuildRecommendationSource? source;
                      for (final item in recommendation.sources) {
                        if (item.videoId == e.videoId) {
                          source = item;
                          break;
                        }
                      }
                      if (source == null ||
                          !isSafeYoutubeGuideUrl(source.sourceUrl)) {
                        return;
                      }
                      _openUrl(_youtubeAt(source.sourceUrl, e.startSeconds));
                    },
                    child: Text(
                      '${_formatTimestamp(e.startSeconds)} 画面表示「${e.exactVisibleText}」',
                      style: theme.textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              }),
            ],
            for (final caveat in recommendation.caveats)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('・$caveat', style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  String _rangeLabel(BuildStatTarget target) {
    final parts = <String>[];
    if (target.min != null) parts.add('${target.min}以上');
    if (target.recommended != null) parts.add('目安 ${target.recommended}');
    if (target.max != null && target.min != null) {
      return ' (${target.min}～${target.max})';
    }
    if (parts.isEmpty) return '';
    return ' (${parts.join(' / ')})';
  }

  String _verdictLabel(StatCompareVerdict verdict) {
    switch (verdict) {
      case StatCompareVerdict.below:
        return '不足気味';
      case StatCompareVerdict.within:
        return '目安内';
      case StatCompareVerdict.above:
        return '超過気味';
      case StatCompareVerdict.unknown:
        return '—';
    }
  }

  Color _verdictColor(ThemeData theme, StatCompareVerdict verdict) {
    switch (verdict) {
      case StatCompareVerdict.within:
        return theme.colorScheme.primary;
      case StatCompareVerdict.below:
        return theme.colorScheme.tertiary;
      case StatCompareVerdict.above:
        return theme.colorScheme.error;
      case StatCompareVerdict.unknown:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  Future<void> _openUrl(String url) async {
    if (!isSafeYoutubeGuideUrl(url)) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await canLaunchUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _youtubeAt(String sourceUrl, double startSeconds) {
    final seconds = startSeconds.floor();
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null) return sourceUrl;
    final params = Map<String, String>.from(uri.queryParameters);
    params['t'] = '${seconds}s';
    return uri.replace(queryParameters: params).toString();
  }

  String _formatTimestamp(double startSeconds) {
    final total = startSeconds.floor();
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
