import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/planning/character_farm_plan.dart';
import '../../domain/planning/growth_route.dart';
import '../../domain/planning/growth_route_request.dart';
import '../../domain/planning/planning_display_labels.dart';
import '../../providers/app_providers.dart';
import '../../providers/growth_providers.dart';
import 'widgets/ley_line_overflow_farm_details.dart';

/// Displays a multi-day growth route.
/// [request] is optional — when null, shows empty guidance.
class GrowthRouteScreen extends ConsumerWidget {
  const GrowthRouteScreen({super.key, this.request});

  final GrowthRouteRequest? request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeAsync =
        request != null ? ref.watch(growthRouteProvider(request!)) : null;
    final farmPlansAsync = request != null
        ? ref.watch(characterFarmPlansProvider(request!))
        : null;
    final charactersAsync = ref.watch(charactersProvider);
    final theme = Theme.of(context);
    final nameById = <String, String>{
      for (final c in charactersAsync.valueOrNull ?? const []) c.id: c.name,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('育成ルート')),
      body: routeAsync == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '育成目標が設定されていません',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            )
          : routeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Text('読み込みエラー', style: theme.textTheme.bodyMedium),
              ),
              data: (route) => _buildRoute(
                context,
                route,
                nameById,
                farmPlansAsync,
              ),
            ),
    );
  }

  Widget _buildRoute(
    BuildContext context,
    GrowthRoute route,
    Map<String, String> nameById,
    AsyncValue<List<CharacterFarmPlan>>? farmPlansAsync,
  ) {
    final theme = Theme.of(context);
    if (route.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '育成目標が設定されていません',
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }

    final budget = route.dailyResinBudget;
    final total = route.totalEstimatedResin;
    final plans = farmPlansAsync?.valueOrNull;
    final headerPlan = _headerPlan(plans);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${route.startDate.month}/${route.startDate.day} 〜 ${route.endDate.month}/${route.endDate.day}',
                  style: theme.textTheme.titleMedium,
                ),
                if (headerPlan != null) ...[
                  Text(
                    '必要樹脂合計：${_fmt(headerPlan.totalResin)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    '自然回復：約${headerPlan.naturalRegenDays}日分',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    '濃縮樹脂：約${headerPlan.condensedResinCount}個分',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (headerPlan.hasLeyLineOverflow)
                    Text(
                      '※地脈の奔流のボーナスは通常樹脂周回のみ対象です（濃縮樹脂では代用できません）',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ] else if (total != null)
                  Text(
                    '合計樹脂 ≈$total',
                    style: theme.textTheme.bodyMedium,
                  ),
                if (budget != null)
                  Text(
                    '目安予算 $budget/日',
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(height: 4),
                Text(
                  '想定ドロップに基づく概算。割当は曜日・優先度優先',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (route.unresolvedCosts.isNotEmpty)
                  Text(
                    '未割当: ${route.unresolvedCosts.length}件',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (farmPlansAsync != null) ...[
          const SizedBox(height: 12),
          Text('キャラ別の必要樹脂', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          farmPlansAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Text(
              '樹脂詳細の読み込みに失敗しました',
              style: theme.textTheme.bodySmall,
            ),
            data: (list) {
              final visible = list
                  .where((p) => p.characterId != '_aggregate')
                  .toList();
              if (visible.isEmpty) {
                return Text('表示できる項目がありません', style: theme.textTheme.bodySmall);
              }
              return Column(
                children: [
                  for (final plan in visible)
                    _CharacterFarmPlanCard(
                      plan: plan,
                      nameById: nameById,
                    ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        Text('日程別', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        ...route.days.map(
          (day) => _DayCard(
            day: day,
            nameById: nameById,
            dailyResinBudget: budget,
          ),
        ),
        if (route.unresolvedCosts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('未割当の項目', style: theme.textTheme.titleSmall),
          ...route.unresolvedCosts.map((id) {
            final type = growthOptionTypeFromOptionId(id);
            final label = type != null
                ? growthOptionTypeLabel(type)
                : '育成項目';
            return ListTile(
              dense: true,
              title: Text(label, style: theme.textTheme.bodySmall),
            );
          }),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'ルールバージョン: ${route.ruleVersion}',
              style: theme.textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  CharacterFarmPlan? _headerPlan(List<CharacterFarmPlan>? plans) {
    if (plans == null || plans.isEmpty) return null;
    for (final p in plans) {
      if (p.characterId == '_aggregate') return p;
    }
    return plans.first;
  }
}

class _CharacterFarmPlanCard extends StatelessWidget {
  const _CharacterFarmPlanCard({
    required this.plan,
    required this.nameById,
  });

  final CharacterFarmPlan plan;
  final Map<String, String> nameById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = nameById[plan.characterId] ?? plan.characterId;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        title: Text(name, style: theme.textTheme.titleSmall),
        subtitle: Text(
          '必要樹脂合計：${_fmt(plan.totalResin)}\n'
          '自然回復：約${plan.naturalRegenDays}日分　'
          '濃縮樹脂：約${plan.condensedResinCount}個分',
          style: theme.textTheme.labelMedium,
        ),
        children: [
          for (final section in plan.sections)
            _FarmSectionTile(section: section),
          if (plan.zeroResinMaterials.isNotEmpty)
            ExpansionTile(
              title: Text('樹脂不要素材', style: theme.textTheme.bodyMedium),
              subtitle: Text(
                '${plan.zeroResinMaterials.length}種',
                style: theme.textTheme.labelSmall,
              ),
              children: [
                for (final line in plan.zeroResinMaterials)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${line.name}：不足${_fmt(line.shortage)}個',
                      style: theme.textTheme.bodySmall,
                    ),
                    subtitle: Text(
                      '必要${_fmt(line.needed)} / 所持${_fmt(line.owned)}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FarmSectionTile extends StatelessWidget {
  const _FarmSectionTile({required this.section});

  final FarmContentSection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overflow = section.leyLineOverflow;
    final eventAccent = scheme.tertiary;
    final runsLabel = section.estimateMode == FarmEstimateMode.range &&
            section.runsMin != null &&
            section.runsMax != null
        ? '推定：約${section.runsMin}～${section.runsMax}回'
        : '約${section.runsExpected}回';
    final resinLabel = section.estimateMode == FarmEstimateMode.range &&
            section.resinMin != null &&
            section.resinMax != null
        ? '${_fmt(section.resinMin!)}～${_fmt(section.resinMax!)}樹脂'
        : '${_fmt(section.resinTotal)}樹脂';

    final overflowSubtitle = overflow == null
        ? section.contentLabel
        : '${section.contentLabel}\n'
            '${leyLineOverflowActiveLabel(overflow.eventDisplayName)}\n'
            '通常報酬換算：約${overflow.normalEquivalentRuns}回分\n'
            '${overflow.isMaxEstimate ? 'ボーナス適用：最大${overflow.dailyBonusLimit}回' : '本日のボーナス残り：${overflow.remainingBonusCapacity}回'}';

    return ExpansionTile(
      title: Text.rich(
        TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(text: '${section.title}　　$resinLabel　'),
            TextSpan(
              text: runsLabel,
              style: TextStyle(
                color: overflow != null ? eventAccent : null,
                fontWeight: overflow != null ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      ),
      subtitle: Text(
        overflowSubtitle,
        style: theme.textTheme.labelSmall?.copyWith(
          color: overflow != null ? eventAccent : null,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (overflow != null) ...[
                LeyLineOverflowFarmDetails(overflow: overflow),
              ] else ...[
                Text(
                  '・${section.contentLabel}：約${section.runsExpected}回',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '・必要樹脂：約${_fmt(section.resinTotal)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (section.estimateMode == FarmEstimateMode.expected)
                Text(
                  '・計算：目安（期待値）',
                  style: theme.textTheme.labelSmall,
                )
              else
                Text(
                  '・計算：推定（ドロップ幅）／目安 ${section.runsExpected}回',
                  style: theme.textTheme.labelSmall,
                ),
              if (section.weeksMin != null && section.weeksMax != null)
                Text(
                  '・推定：${section.weeksMin}～${section.weeksMax}週間'
                  '（討伐目安：${section.runsExpected}回）',
                  style: theme.textTheme.bodySmall,
                ),
              if (section.openWeekdayLabels.isNotEmpty)
                Text(
                  '・開放曜日：${section.openWeekdayLabels.join('・')}',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
              Text('根拠：${section.rationale}', style: theme.textTheme.labelSmall),
              const Divider(),
              for (final line in section.materials) ...[
                Text(
                  line.materialId == '__mora__'
                      ? '不足モラ：${_fmt(line.shortage)}'
                      : line.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (line.materialId != '__mora__')
                  Text(
                    '必要${_fmt(line.needed)} / 所持${_fmt(line.owned)} / '
                    '不足${_fmt(line.shortage)}'
                    '${line.sourceLabel != null ? '　入手先：${line.sourceLabel}' : ''}',
                    style: theme.textTheme.labelSmall,
                  ),
                const SizedBox(height: 4),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.nameById,
    this.dailyResinBudget,
  });
  final GrowthRouteDay day;
  final Map<String, String> nameById;
  final int? dailyResinBudget;

  String _weekdayLabel(int w) {
    const labels = ['月', '火', '水', '木', '金', '土', '日'];
    return labels[(w - 1).clamp(0, 6)];
  }

  String _actionTitle(GrowthRouteAction a) {
    final charName = a.characterId == null
        ? null
        : nameById[a.characterId!];
    final typeKey = a.reasons.isNotEmpty
        ? a.reasons.first
        : growthOptionTypeFromOptionId(a.optionId) ?? a.optionId;
    final typeLabel = growthOptionTypeLabel(typeKey);
    if (charName != null && charName.isNotEmpty) {
      return '$charName — $typeLabel';
    }
    return typeLabel;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = day.estimatedResinUsed;
    final overBudget = dailyResinBudget != null &&
        used != null &&
        used > dailyResinBudget!;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${day.date.month}/${day.date.day}（${_weekdayLabel(day.weekday)}）',
              style: theme.textTheme.titleSmall,
            ),
            if (used != null)
              Text(
                dailyResinBudget != null
                    ? '樹脂: ≈$used / 目安$dailyResinBudget'
                    : '樹脂: ≈$used',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: overBudget ? theme.colorScheme.error : null,
                ),
              ),
            const Divider(),
            if (day.actions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('予定なし', style: theme.textTheme.bodySmall),
              )
            else
              ...day.actions.map(
                (a) => ListTile(
                  dense: true,
                  title: Text(
                    _actionTitle(a),
                    style: theme.textTheme.bodySmall,
                  ),
                  subtitle: Text(
                    '${growthActionTypeLabel(a.actionType)} · 優先度 ${a.priority}'
                    '${a.estimatedResinCost != null ? ' · 樹脂 ≈${a.estimatedResinCost}' : ''}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _fmt(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return n < 0 ? '-$buf' : buf.toString();
}
