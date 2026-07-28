import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/game_display.dart';
import '../../../domain/models/master_models.dart';
import '../../../domain/character_stats.dart';
import '../../../domain/level_progression.dart';
import '../../../domain/models/calculation_models.dart';
import '../../../domain/models/character_build_snapshot.dart';
import '../../../providers/character_detail_providers.dart';
import 'recommended_stats_card.dart';

/// ステータスタブ: 現在（取得情報基準）と変更後（編集状態）を比較表示する
class SimulatedStatsSection extends ConsumerWidget {
  const SimulatedStatsSection({
    super.key,
    required this.character,
    required this.promotes,
    required this.baseline,
    required this.simulated,
  });

  final MasterCharacter character;
  final List<PromoteStage> promotes;

  /// 取得情報（HoYoLAB / 保存値）のスナップショット
  final CharacterBuildSnapshot baseline;

  /// 現在の編集状態（シミュレーション値）
  final CharacterBuildSnapshot simulated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(avatarDetailProvider(character.id));
    final baseWeaponAsync = ref.watch(weaponStatsProvider(baseline.weaponId));
    final simWeaponAsync = ref.watch(weaponStatsProvider(simulated.weaponId));

    if (detailAsync.isLoading ||
        baseWeaponAsync.isLoading ||
        simWeaponAsync.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final avatarStats = detailAsync.valueOrNull?.stats;
    if (avatarStats == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'ステータス計算用データを取得できませんでした。\nネットワーク接続を確認して画面を開き直してください。',
        ),
      );
    }

    final setsAsync = ref.watch(artifactSetsProvider);
    final sets = setsAsync.valueOrNull ?? const [];

    StatValues compute(
      CharacterBuildSnapshot snapshot,
      WeaponStatsData? weaponStats,
    ) {
      final activeSetEffects = resolveActiveTwoPieceSetEffects(
        artifacts: snapshot.artifacts,
        sets: sets,
      );
      return computeCharacterStats(
        avatarStats: avatarStats,
        element: character.element,
        level: snapshot.level,
        ascension: getAscensionForLevel(snapshot.level, promotes),
        weapon: weaponStats?.statsAtLevel(snapshot.weaponLevel),
        artifacts: snapshot.artifacts,
        activeSetEffects: activeSetEffects,
      );
    }

    final current = compute(baseline, baseWeaponAsync.valueOrNull);
    final sim = compute(simulated, simWeaponAsync.valueOrNull);

    final elementLabel =
        '${elementLabelMap[character.element] ?? character.element}元素ダメージ';
    final rows = buildStatDeltaRows(
      current: current,
      simulated: sim,
      elementLabel: elementLabel,
    );

    final theme = Theme.of(context);
    final hasChanges = rows.any((r) => r.hasChange);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BuildSummaryRow(label: '現在（取得情報）', snapshot: baseline),
        const SizedBox(height: 4),
        _BuildSummaryRow(label: '変更後（編集）', snapshot: simulated),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(flex: 3, child: SizedBox()),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '現在',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '編集後',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '差分',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                ...rows.map((row) => _StatRow(row: row)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (!hasChanges)
          Text(
            '取得情報から変更はありません。レベル・武器・聖遺物を変更すると差分が表示されます。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        Text(
          '※ 基礎・武器・聖遺物・2セット効果の合算。条件付き4セット・武器パッシブ・天賦補正は含みません。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        RecommendedStatsCard(
          characterId: character.id,
          currentStats: current,
        ),
      ],
    );
  }
}

class _BuildSummaryRow extends StatelessWidget {
  const _BuildSummaryRow({required this.label, required this.snapshot});

  final String label;
  final CharacterBuildSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weapon = snapshot.weaponName.isEmpty
        ? '武器なし'
        : '${snapshot.weaponName} Lv.${snapshot.weaponLevel}';
    return Text(
      '$label: Lv.${snapshot.level} · 凸${snapshot.constellation} · $weapon · '
      '天賦 ${snapshot.talentNormal}/${snapshot.talentSkill}/${snapshot.talentBurst}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.row});

  final StatDeltaRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deltaColor = !row.hasChange
        ? theme.colorScheme.onSurfaceVariant
        : row.delta > 0
            ? Colors.green.shade600
            : theme.colorScheme.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(row.label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatStatValue(row.key, row.current),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatStatValue(row.key, row.simulated),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: row.hasChange ? FontWeight.w600 : null,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              row.hasChange ? formatStatDelta(row.key, row.delta) : '±0',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: deltaColor,
                fontWeight: row.hasChange ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
