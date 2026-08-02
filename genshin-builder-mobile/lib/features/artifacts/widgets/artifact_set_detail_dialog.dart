import 'package:flutter/material.dart';

import '../../../domain/artifacts/artifact_set_overview.dart';
import '../../shared/game_icon_image.dart';
import 'character_icon_with_badge.dart';
import 'equipped_character_set_icon.dart';

/// 聖遺物セット詳細ポップアップ。
/// 背景タップ・戻る・× で閉じる。
Future<void> showArtifactSetDetailDialog({
  required BuildContext context,
  required ArtifactSetOverview overview,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => ArtifactSetDetailDialog(overview: overview),
  );
}

class ArtifactSetDetailDialog extends StatelessWidget {
  const ArtifactSetDetailDialog({super.key, required this.overview});

  final ArtifactSetOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final set = overview.set;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(set.name, style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '閉じる',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: GameIconImage(
                        iconUrl: set.iconUrl,
                        size: 72,
                        borderRadius: 12,
                      ),
                    ),
                    if (overview.twoPieceEffect.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text('2セット効果', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        overview.twoPieceEffect,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (overview.fourPieceEffect.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('4セット効果', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        overview.fourPieceEffect,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('装備キャラクター', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    if (overview.equippedCharacters.isEmpty)
                      Text(
                        '該当なし',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final e in overview.equippedCharacters)
                            EquippedCharacterSetIcon(entry: e),
                        ],
                      ),
                    const SizedBox(height: 16),
                    Text('推奨キャラクター', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Akasha 公開ビルドのセット使用率（不足分は設定フォールバック）',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (overview.recommendedCharacters.isEmpty)
                      Text(
                        '未設定',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final r in overview.recommendedCharacters)
                            CharacterIconWithBadge(
                              characterId: r.character.id,
                              iconUrl: r.character.iconUrl,
                              name:
                                  r.usageRate == null
                                      ? r.character.name
                                      : '${r.character.name}（${(r.usageRate! * 100).round()}%）',
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
