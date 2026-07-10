import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/master_models.dart';
import '../../shared/game_icon_image.dart';

/// シリーズ内素材を横並びで各必要数表示（最大 / 次の段階）
class DailyMaterialNeedRow extends StatelessWidget {
  const DailyMaterialNeedRow({
    super.key,
    required this.materials,
    required this.remainingByMaterialId,
    required this.nextStageByMaterialId,
    required this.fmt,
    this.compact = false,
  });

  final List<MasterMaterial> materials;
  final Map<String, int> remainingByMaterialId;
  final Map<String, int> nextStageByMaterialId;
  final NumberFormat fmt;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconSize = compact ? 28.0 : 40.0;

    return Row(
      children: [
        for (final material in materials)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GameIconImage(
                  iconUrl: material.iconUrl,
                  size: iconSize,
                  fallback: Icon(
                    Icons.inventory_2_outlined,
                    size: iconSize * 0.5,
                  ),
                ),
                SizedBox(height: compact ? 2 : 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _formatNeed(
                      remainingByMaterialId[material.id] ?? 0,
                      nextStageByMaterialId[material.id] ?? 0,
                      fmt,
                    ),
                    style: (compact
                            ? theme.textTheme.labelSmall
                            : theme.textTheme.labelMedium)
                        ?.copyWith(
                      color: (remainingByMaterialId[material.id] ?? 0) > 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _formatNeed(int total, int next, NumberFormat fmt) {
    return '×${fmt.format(total)} (${fmt.format(next)})';
  }
}
