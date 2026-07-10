import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/master_models.dart';
import '../../../domain/daily_materials/daily_material_models.dart';
import 'material_need_row.dart';

class RemainingBadge extends StatelessWidget {
  const RemainingBadge({
    super.key,
    required this.status,
    required this.materials,
    required this.remainingByMaterialId,
    required this.nextStageByMaterialId,
    required this.fmt,
  });

  final DailyRemainingStatus status;
  final List<MasterMaterial> materials;
  final Map<String, int> remainingByMaterialId;
  final Map<String, int> nextStageByMaterialId;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (status) {
      case DailyRemainingStatus.needed:
        return SizedBox(
          width: 132,
          child: DailyMaterialNeedRow(
            materials: materials,
            remainingByMaterialId: remainingByMaterialId,
            nextStageByMaterialId: nextStageByMaterialId,
            fmt: fmt,
            compact: true,
          ),
        );
      case DailyRemainingStatus.complete:
        return Text(
          '✓ 完成済み',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.tertiary,
          ),
        );
      case DailyRemainingStatus.unknown:
        return const SizedBox.shrink();
    }
  }
}
