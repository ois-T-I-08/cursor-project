import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/game_display.dart';
import '../../../domain/models/amber_detail_models.dart';
import '../../../domain/models/master_models.dart';
import '../../../providers/character_detail_providers.dart';
import '../../shared/game_icon_image.dart';
import 'constellation_icons_row.dart';
import 'investment_priority_badge.dart';

/// Character detail header: icon, name, constellations, level, element
class CharacterDetailHeader extends ConsumerWidget {
  const CharacterDetailHeader({
    super.key,
    required this.character,
    required this.level,
    required this.constellation,
    this.onConstellationChanged,
  });

  final MasterCharacter character;

  /// 表示用レベル（シミュレーション値可）
  final int level;

  /// 表示用凸数 0〜6（取得データと分離した表示状態）
  final int constellation;

  final ValueChanged<int>? onConstellationChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final elementLabel =
        elementLabelMap[character.element] ?? character.element;
    final weaponLabel =
        weaponTypeLabelMap[character.weaponType] ?? character.weaponType;
    final elementColor = elementColorMap.containsKey(character.element)
        ? Color(elementColorMap[character.element]!)
        : theme.colorScheme.primary;

    final detailAsync = ref.watch(avatarDetailProvider(character.id));
    final constellations = detailAsync.valueOrNull?.constellations ??
        const <ConstellationDetailData>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GameIconImage(iconUrl: character.iconUrl, size: 64, borderRadius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        character.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InvestmentPriorityBadge(characterId: character.id),
                  ],
                ),
                const SizedBox(height: 4),
                ConstellationIconsRow(
                  unlockedCount: constellation,
                  elementColor: elementColor,
                  constellations: constellations,
                  onConstellationSelected: onConstellationChanged,
                  iconSize: 18,
                  spacing: 2,
                ),
                const SizedBox(height: 2),
                Text(
                  'Lv.$level · 凸$constellation',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _InfoChip(
                      label: elementLabel,
                      background: elementColor.withValues(alpha: 0.18),
                      foreground: elementColor,
                    ),
                    _InfoChip(
                      label: '${character.rarity}★',
                      background: theme.colorScheme.primaryContainer,
                      foreground: theme.colorScheme.onPrimaryContainer,
                    ),
                    _InfoChip(
                      label: weaponLabel,
                      background: theme.colorScheme.surfaceContainerHighest,
                      foreground: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
