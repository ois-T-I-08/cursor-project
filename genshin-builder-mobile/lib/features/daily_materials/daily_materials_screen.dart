import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/daily_materials/daily_material_models.dart';
import '../../providers/daily_materials_providers.dart';
import 'widgets/series_card.dart';

class DailyMaterialsScreen extends ConsumerStatefulWidget {
  const DailyMaterialsScreen({super.key});

  @override
  ConsumerState<DailyMaterialsScreen> createState() =>
      _DailyMaterialsScreenState();
}

class _DailyMaterialsScreenState extends ConsumerState<DailyMaterialsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final int _todayWeekday;

  static const _weekdays = [
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  ];

  @override
  void initState() {
    super.initState();
    _todayWeekday = genshinIsoWeekday();
    final initialIndex = _weekdays.indexOf(_todayWeekday).clamp(0, 6);
    _tabController = TabController(
      length: _weekdays.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int get _selectedWeekday => _weekdays[_tabController.index];

  Future<void> _refresh() async {
    ref.invalidate(dailyMaterialsPlanProvider(_selectedWeekday));
    await ref.read(dailyMaterialsPlanProvider(_selectedWeekday).future);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planAsync = ref.watch(dailyMaterialsPlanProvider(_selectedWeekday));

    return Scaffold(
      appBar: AppBar(
        title: const Text('曜日素材'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          tabs: [
            for (final day in _weekdays)
              Tab(
                child: Text(
                  weekdayLabelsJa[day] ?? '$day',
                  style: TextStyle(
                    fontWeight:
                        day == _todayWeekday ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('読み込みエラー: $e')),
        data: (plan) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  _selectedWeekday == _todayWeekday
                      ? '今日入手できる素材'
                      : '${weekdayLabelsJa[_selectedWeekday]}曜日に入手できる素材',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Text('天賦素材', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (plan.talentCards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'この曜日の天賦素材はありません',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final card in plan.talentCards)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DailyMaterialSeriesCard(
                        card: card,
                        emptyConsumersLabel: '使用キャラクターなし',
                        onConsumerTap: (id) =>
                            context.push('/characters/$id'),
                      ),
                    ),
                const SizedBox(height: 8),
                Text('武器突破素材', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (plan.weaponCards.isEmpty)
                  Text(
                    'この曜日の武器突破素材はありません',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (final card in plan.weaponCards)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DailyMaterialSeriesCard(
                        card: card,
                        emptyConsumersLabel: '使用武器なし',
                        showGroupLabels: true,
                      ),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}
