import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/master_models.dart';
import '../../../domain/daily_materials/daily_material_models.dart';
import '../../shared/game_icon_image.dart';
import 'remaining_badge.dart';

class CharacterConsumerTile extends StatelessWidget {
  const CharacterConsumerTile({
    super.key,
    required this.consumer,
    required this.materials,
    this.onTap,
  });

  final DailyMaterialConsumer consumer;
  final List<MasterMaterial> materials;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = NumberFormat('#,###');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            GameIconImage(
              iconUrl: consumer.iconUrl,
              size: 36,
              fallback: const Icon(Icons.person_outline, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    consumer.name,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (consumer.isOwned || consumer.isBuilding)
                    Text(
                      [
                        if (consumer.isOwned) '所持',
                        if (consumer.isBuilding) '育成中',
                      ].join(' · '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            RemainingBadge(
              status: consumer.remainingStatus,
              materials: materials,
              remainingByMaterialId: consumer.remainingByMaterialId,
              nextStageByMaterialId: consumer.nextStageByMaterialId,
              fmt: fmt,
            ),
          ],
        ),
      ),
    );
  }
}
