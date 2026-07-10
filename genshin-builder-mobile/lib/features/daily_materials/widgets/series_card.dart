import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/daily_materials/daily_material_models.dart';
import '../../shared/game_icon_image.dart';
import 'character_consumer_tile.dart';
import 'material_need_row.dart';
import 'weapon_consumer_tile.dart';

class DailyMaterialSeriesCard extends StatelessWidget {
  const DailyMaterialSeriesCard({
    super.key,
    required this.card,
    required this.emptyConsumersLabel,
    this.showGroupLabels = false,
    this.onConsumerTap,
  });

  final DailyMaterialSeriesCardData card;
  final String emptyConsumersLabel;
  final bool showGroupLabels;
  final void Function(String id)? onConsumerTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = NumberFormat('#,###');
    final headerIcon = card.displayMaterial;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GameIconImage(
                  iconUrl: headerIcon?.iconUrl,
                  size: 44,
                  fallback: const Icon(Icons.menu_book_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '「${card.series.name}」シリーズ',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        card.series.region,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DailyMaterialNeedRow(
              materials: card.materials,
              remainingByMaterialId: card.remainingByMaterialId,
              nextStageByMaterialId: card.nextStageByMaterialId,
              fmt: fmt,
            ),
            const Divider(height: 20),
            if (card.consumerGroups.isEmpty)
              Text(
                emptyConsumersLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final group in card.consumerGroups) ...[
                if (showGroupLabels)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Text(
                      group.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                for (final consumer in group.consumers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: showGroupLabels
                        ? WeaponConsumerTile(
                            consumer: consumer,
                            materials: card.materials,
                          )
                        : CharacterConsumerTile(
                            consumer: consumer,
                            materials: card.materials,
                            onTap: onConsumerTap == null
                                ? null
                                : () => onConsumerTap!(consumer.id),
                          ),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}
