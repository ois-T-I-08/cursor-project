import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/akasha/akasha_weapon_usage.dart';
import '../../../domain/build_recommendations/build_recommendation.dart';
import '../../../domain/models/master_models.dart';
import '../../../providers/build_recommendation_providers.dart';
import '../../../providers/character_detail_providers.dart';
import '../../shared/game_icon_image.dart';
import 'guide_section_state.dart';
import 'guide_source_label.dart';

/// おすすめ武器: Akasha 使用率と YouTube おすすめを別グループで表示。
class CharacterWeaponInsightsSection extends ConsumerStatefulWidget {
  const CharacterWeaponInsightsSection({
    super.key,
    required this.characterId,
    required this.weapons,
  });

  final String characterId;
  final List<MasterWeapon> weapons;

  @override
  ConsumerState<CharacterWeaponInsightsSection> createState() =>
      _CharacterWeaponInsightsSectionState();
}

class _CharacterWeaponInsightsSectionState
    extends ConsumerState<CharacterWeaponInsightsSection> {
  bool _akashaExpanded = false;
  bool _youtubeExpanded = false;

  @override
  Widget build(BuildContext context) {
    final usageAsync =
        ref.watch(weaponUsageRatesProvider(widget.characterId));
    final guideAsync =
        ref.watch(buildRecommendationProvider(widget.characterId));

    return CharacterWeaponInsightsView(
      weapons: widget.weapons,
      akashaAsync: usageAsync,
      guideAsync: guideAsync,
      akashaExpanded: _akashaExpanded,
      youtubeExpanded: _youtubeExpanded,
      onToggleAkashaExpand: () =>
          setState(() => _akashaExpanded = !_akashaExpanded),
      onToggleYoutubeExpand: () =>
          setState(() => _youtubeExpanded = !_youtubeExpanded),
      onRetryAkasha: () =>
          ref.invalidate(weaponUsageRatesProvider(widget.characterId)),
      onRetryGuide: () =>
          ref.invalidate(buildRecommendationProvider(widget.characterId)),
    );
  }
}

/// Provider 非依存の表示本体（Widget テスト用）
class CharacterWeaponInsightsView extends StatelessWidget {
  const CharacterWeaponInsightsView({
    super.key,
    required this.weapons,
    required this.akashaAsync,
    required this.guideAsync,
    this.akashaExpanded = false,
    this.youtubeExpanded = false,
    this.onToggleAkashaExpand,
    this.onToggleYoutubeExpand,
    this.onRetryAkasha,
    this.onRetryGuide,
  });

  final List<MasterWeapon> weapons;
  final AsyncValue<WeaponUsageSnapshot> akashaAsync;
  final AsyncValue<CharacterBuildRecommendation?> guideAsync;
  final bool akashaExpanded;
  final bool youtubeExpanded;
  final VoidCallback? onToggleAkashaExpand;
  final VoidCallback? onToggleYoutubeExpand;
  final VoidCallback? onRetryAkasha;
  final VoidCallback? onRetryGuide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('おすすめ武器', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '使用率（実績）と攻略おすすめは別の情報です。混同せず比較してください。',
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
          data: (snap) => _AkashaWeaponsGroup(
            snapshot: snap,
            weapons: weapons,
            expanded: akashaExpanded,
            onToggleExpand: onToggleAkashaExpand,
          ),
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
          data: (rec) => _YoutubeWeaponsGroup(
            recommendation: rec,
            weapons: weapons,
            expanded: youtubeExpanded,
            onToggleExpand: onToggleYoutubeExpand,
          ),
        ),
      ],
    );
  }
}

class _AkashaWeaponsGroup extends StatelessWidget {
  const _AkashaWeaponsGroup({
    required this.snapshot,
    required this.weapons,
    required this.expanded,
    this.onToggleExpand,
  });

  final WeaponUsageSnapshot snapshot;
  final List<MasterWeapon> weapons;
  final bool expanded;
  final VoidCallback? onToggleExpand;

  @override
  Widget build(BuildContext context) {
    if (!snapshot.isFromRemote || snapshot.sampleSize <= 0) {
      return const GuideSectionMessage(message: '使用率データがありません。');
    }

    final byId = {for (final w in weapons) w.id: w};
    final ranked = snapshot.rates.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final items = <_RankedWeapon>[];
    var rank = 0;
    for (final e in ranked) {
      if (e.value <= 0) continue;
      rank += 1;
      items.add(
        _RankedWeapon(
          weapon: byId[e.key],
          weaponId: e.key,
          rate: e.value,
          rank: rank,
        ),
      );
    }

    if (items.isEmpty) {
      return const GuideSectionMessage(message: '集計対象の武器使用率がありません。');
    }

    final visible = expanded ? items : items.take(3).toList();
    final theme = Theme.of(context);
    final fetched = snapshot.fetchedAt.toLocal();
    final dateLabel =
        '${fetched.year}/${fetched.month.toString().padLeft(2, '0')}/${fetched.day.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '公開ビルド集計 n=${snapshot.sampleSize} · $dateLabel',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ...visible.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _WeaponInsightTile(
              title: item.weapon?.name ?? '武器 ID ${item.weaponId}',
              subtitle: item.weapon != null
                  ? '${item.weapon!.rarity}★ · 使用率 ${_formatRate(item.rate)} · ${item.rank}位'
                  : '使用率 ${_formatRate(item.rate)} · ${item.rank}位',
              iconUrl: item.weapon?.iconUrl,
              fallback: item.weapon?.name,
            ),
          ),
        ),
        if (items.length > 3 && onToggleExpand != null)
          TextButton(
            onPressed: onToggleExpand,
            child: Text(expanded ? '閉じる' : '残り ${items.length - 3} 件を表示'),
          ),
      ],
    );
  }

  String _formatRate(double rate) => '${(rate * 100).toStringAsFixed(1)}%';
}

class _YoutubeWeaponsGroup extends StatelessWidget {
  const _YoutubeWeaponsGroup({
    required this.recommendation,
    required this.weapons,
    required this.expanded,
    this.onToggleExpand,
  });

  final CharacterBuildRecommendation? recommendation;
  final List<MasterWeapon> weapons;
  final bool expanded;
  final VoidCallback? onToggleExpand;

  @override
  Widget build(BuildContext context) {
    if (recommendation == null) {
      return const GuideSectionMessage(
        message: 'おすすめ情報はまだ登録されていません。',
      );
    }

    final items = recommendation!.youtubeWeapons;
    if (items.isEmpty) {
      return const GuideSectionMessage(
        message: '攻略動画のおすすめ武器はまだ登録されていません。',
      );
    }

    final byId = {for (final w in weapons) w.id: w};
    final byName = {for (final w in weapons) w.name: w};
    final visible = expanded ? items : items.take(3).toList();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recommendation!.freshnessCaption != null)
          Text(
            recommendation!.freshnessCaption!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (recommendation!.freshnessCaption != null) const SizedBox(height: 8),
        ...visible.map((item) {
          final master = (item.weaponId != null ? byId[item.weaponId!] : null) ??
              (item.displayName != null ? byName[item.displayName!] : null);
          final title = master?.name ??
              item.displayName ??
              (item.weaponId != null ? '未登録武器 (${item.weaponId})' : '武器');
          final subtitleParts = <String>[
            if (master != null) '${master.rarity}★',
            if (item.rank != null) 'おすすめ ${item.rank}位',
            if (item.recommendationLevel != null)
              item.recommendationLevel!.label,
            if (item.isLegacy) '旧形式の参考情報',
          ];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _WeaponInsightTile(
              title: title,
              subtitle: subtitleParts.join(' · '),
              iconUrl: master?.iconUrl,
              fallback: title,
              reason: item.reason,
              conditions: item.conditions,
              citationCaption: item.citation?.caption,
            ),
          );
        }),
        if (items.length > 3 && onToggleExpand != null)
          TextButton(
            onPressed: onToggleExpand,
            child: Text(
              expanded ? '閉じる' : '残り ${items.length - 3} 件を表示',
            ),
          ),
      ],
    );
  }
}

class _RankedWeapon {
  const _RankedWeapon({
    required this.weaponId,
    required this.rate,
    required this.rank,
    this.weapon,
  });

  final MasterWeapon? weapon;
  final String weaponId;
  final double rate;
  final int rank;
}

class _WeaponInsightTile extends StatelessWidget {
  const _WeaponInsightTile({
    required this.title,
    required this.subtitle,
    this.iconUrl,
    this.fallback,
    this.reason,
    this.conditions = const [],
    this.citationCaption,
  });

  final String title;
  final String subtitle;
  final String? iconUrl;
  final String? fallback;
  final String? reason;
  final List<String> conditions;
  final String? citationCaption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GameIconImage(
              iconUrl: iconUrl,
              size: 40,
              borderRadius: 8,
              fallback: Text(
                (fallback != null && fallback!.isNotEmpty)
                    ? fallback![0]
                    : '?',
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
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (reason != null && reason!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        reason!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (conditions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '条件: ${conditions.join(' / ')}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (citationCaption != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '出典: $citationCaption',
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
