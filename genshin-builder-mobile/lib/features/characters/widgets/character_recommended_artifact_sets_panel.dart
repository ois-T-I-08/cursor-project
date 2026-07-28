import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/artifacts/character_recommended_artifact_sets.dart';
import '../../../domain/models/amber_detail_models.dart';
import '../../../providers/artifact_sets_page_providers.dart';
import '../../shared/game_icon_image.dart';

/// キャラ詳細・聖遺物タブのおすすめセット表示。
class CharacterRecommendedArtifactSetsPanel extends ConsumerWidget {
  const CharacterRecommendedArtifactSetsPanel({
    super.key,
    required this.characterId,
  });

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      characterRecommendedArtifactSetsProvider(characterId),
    );
    final theme = Theme.of(context);

    return async.when(
      loading:
          () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('おすすめ聖遺物セット', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Akasha 公開ビルドのセット使用率（不足分は設定フォールバック）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RecommendedSetTile(item: item),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecommendedSetTile extends StatelessWidget {
  const _RecommendedSetTile({required this.item});

  final CharacterRecommendedArtifactSet item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final set = item.set;
    final rateLabel =
        item.usageRate == null ? null : '${(item.usageRate! * 100).round()}%';
    final effectPreview = set.effects.isNotEmpty ? set.effects.first : null;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showSetEffects(context, set, rateLabel),
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
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (effectPreview != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        effectPreview,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (rateLabel != null) ...[
                const SizedBox(width: 8),
                Text(
                  rateLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showSetEffects(
    BuildContext context,
    ArtifactSetDetail set,
    String? rateLabel,
  ) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                GameIconImage(
                  iconUrl: set.iconUrl,
                  size: 36,
                  borderRadius: 6,
                  fallback: Text(set.name.isNotEmpty ? set.name[0] : '?'),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(set.name)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rateLabel != null) ...[
                  Text(
                    '使用率 $rateLabel',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (set.effects.isEmpty)
                  Text(
                    'セット効果なし',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (var i = 0; i < set.effects.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    Text(
                      '${i == 0 ? '2セット' : '4セット'}: ${set.effects[i]}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('閉じる'),
              ),
            ],
          ),
    );
  }
}
