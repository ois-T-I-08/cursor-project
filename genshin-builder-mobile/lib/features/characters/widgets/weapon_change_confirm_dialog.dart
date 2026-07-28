import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/game_display.dart';
import '../../../data/amber/amber_detail_repository.dart';
import '../../../domain/models/master_models.dart';
import '../../../domain/character_stats.dart';
import '../../../domain/level_progression.dart';
import '../../../domain/models/calculation_models.dart';
import '../../../domain/models/character_build_snapshot.dart';
import '../../../providers/character_detail_providers.dart';
import '../../shared/game_icon_image.dart';

/// Weapon change confirmation dialog with simulated stat deltas.
Future<bool?> showWeaponChangeConfirmDialog({
  required BuildContext context,
  required WidgetRef ref,
  required MasterCharacter character,
  required List<PromoteStage> promotes,
  required CharacterBuildSnapshot currentBuild,
  required MasterWeapon? currentWeapon,
  required MasterWeapon newWeapon,
}) {
  final repository = ref.read(amberDetailRepositoryProvider);
  return showDialog<bool>(
    context: context,
    builder:
        (context) => _WeaponChangeConfirmDialog(
          repository: repository,
          character: character,
          promotes: promotes,
          currentBuild: currentBuild,
          currentWeapon: currentWeapon,
          newWeapon: newWeapon,
        ),
  );
}

class _DialogData {
  const _DialogData({this.rows});

  final List<StatDeltaRow>? rows;
}

class _WeaponChangeConfirmDialog extends StatefulWidget {
  const _WeaponChangeConfirmDialog({
    required this.repository,
    required this.character,
    required this.promotes,
    required this.currentBuild,
    required this.currentWeapon,
    required this.newWeapon,
  });

  final AmberDetailRepository repository;
  final MasterCharacter character;
  final List<PromoteStage> promotes;
  final CharacterBuildSnapshot currentBuild;
  final MasterWeapon? currentWeapon;
  final MasterWeapon newWeapon;

  @override
  State<_WeaponChangeConfirmDialog> createState() =>
      _WeaponChangeConfirmDialogState();
}

class _WeaponChangeConfirmDialogState
    extends State<_WeaponChangeConfirmDialog> {
  late final Future<_DialogData> _future = _loadDeltas();

  Future<_DialogData> _loadDeltas() async {
    try {
      final detail = await widget.repository.getAvatarDetail(
        widget.character.id,
      );
      final avatarStats = detail?.stats;
      if (avatarStats == null) return const _DialogData();

      final currentWeaponStats =
          widget.currentBuild.weaponId.isEmpty
              ? null
              : await widget.repository.getWeaponStats(
                widget.currentBuild.weaponId,
              );
      final newWeaponStats = await widget.repository.getWeaponStats(
        widget.newWeapon.id,
      );

      final build = widget.currentBuild;
      final ascension = getAscensionForLevel(build.level, widget.promotes);

      final sets = await widget.repository.getArtifactSets();
      final activeSetEffects = resolveActiveTwoPieceSetEffects(
        artifacts: build.artifacts,
        sets: sets,
      );

      StatValues compute(WeaponStatsData? weaponStats) => computeCharacterStats(
        avatarStats: avatarStats,
        element: widget.character.element,
        level: build.level,
        ascension: ascension,
        weapon: weaponStats?.statsAtLevel(build.weaponLevel),
        artifacts: build.artifacts,
        activeSetEffects: activeSetEffects,
      );

      final elementLabel =
          '${elementLabelMap[widget.character.element] ?? widget.character.element}元素ダメージ';
      return _DialogData(
        rows: buildStatDeltaRows(
          current: compute(currentWeaponStats),
          simulated: compute(newWeaponStats),
          elementLabel: elementLabel,
        ),
      );
    } catch (_) {
      return const _DialogData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = widget.currentBuild.weaponLevel;

    return AlertDialog(
      title: const Text('武器変更確認'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WeaponRow(
                label: '現在',
                name:
                    widget.currentWeapon?.name ??
                    (widget.currentBuild.weaponName.isEmpty
                        ? '武器なし'
                        : widget.currentBuild.weaponName),
                iconUrl: widget.currentWeapon?.iconUrl,
                level: widget.currentBuild.weaponId.isEmpty ? null : level,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Center(child: Icon(Icons.arrow_downward, size: 20)),
              ),
              _WeaponRow(
                label: '変更後',
                name: widget.newWeapon.name,
                iconUrl: widget.newWeapon.iconUrl,
                level: level,
              ),
              const Divider(height: 24),
              Text('予想変化', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              FutureBuilder<_DialogData>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  final rows = snapshot.data?.rows;
                  if (rows == null) {
                    return Text(
                      'ステータス変化を計算できませんでした（オフライン等）。\nこのまま変更できます。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  }
                  final changed = rows.where((r) => r.hasChange).toList();
                  if (changed.isEmpty) {
                    return Text(
                      'ステータスの変化はありません。',
                      style: theme.textTheme.bodySmall,
                    );
                  }
                  return Column(
                    children:
                        changed
                            .map(
                              (row) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        row.label,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                    ),
                                    Text(
                                      formatStatDelta(row.key, row.delta),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color:
                                                row.delta > 0
                                                    ? Colors.green.shade600
                                                    : theme.colorScheme.error,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                '※ 武器効果（パッシブ）・セット効果は含まれません。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('変更する'),
        ),
      ],
    );
  }
}

class _WeaponRow extends StatelessWidget {
  const _WeaponRow({
    required this.label,
    required this.name,
    required this.iconUrl,
    required this.level,
  });

  final String label;
  final String name;
  final String? iconUrl;
  final int? level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        GameIconImage(iconUrl: iconUrl, size: 36),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            level == null ? name : '$name\nLv.$level',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
