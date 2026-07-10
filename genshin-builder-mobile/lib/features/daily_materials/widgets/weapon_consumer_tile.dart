import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/master_models.dart';
import '../../../domain/daily_materials/daily_material_models.dart';
import '../../shared/game_icon_image.dart';
import 'remaining_badge.dart';

class WeaponConsumerTile extends StatelessWidget {
  const WeaponConsumerTile({
    super.key,
    required this.consumer,
    required this.materials,
  });

  final DailyMaterialConsumer consumer;
  final List<MasterMaterial> materials;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = NumberFormat('#,###');
    final stars = consumer.rarity != null ? ' ${'★' * consumer.rarity!}' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GameIconImage(
                iconUrl: consumer.iconUrl,
                size: 40,
                fallback: const Icon(Icons.sports_mma_outlined, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${consumer.name}$stars',
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (consumer.isOwned) '所持',
                        if (consumer.isEquipped) '装備中',
                        if (consumer.isBuilding) '育成予定',
                        if (consumer.weaponLevel != null)
                          'Lv.${consumer.weaponLevel}',
                        if (consumer.weaponRefinement != null)
                          '精錬${consumer.weaponRefinement}',
                      ].join(' · '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (consumer.equippedCharacters.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final c in consumer.equippedCharacters)
                            Tooltip(
                              message: c.name,
                              child: GameIconImage(
                                iconUrl: c.iconUrl,
                                size: 28,
                                fallback: Text(
                                  c.name.isEmpty ? '?' : c.name.substring(0, 1),
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
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
        ],
      ),
    );
  }
}
