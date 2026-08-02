import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/daily_materials/daily_material_models.dart';
import '../../core/errors/user_facing_error.dart';
import '../../providers/daily_materials_providers.dart';
import '../shared/detail_section_accordion.dart';
import '../shared/game_icon_image.dart';
import '../shared/shell_menu_button.dart';
import 'widgets/series_card.dart';

enum _DailyMaterialViewKind { talent, weapon }

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
  _DailyMaterialViewKind _viewKind = _DailyMaterialViewKind.talent;

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

  /// 閉じたアコーディオンに並べる「必要としている」キャラ（武器は装備キャラ優先）。
  List<_NeedIcon> _needIcons(
    DailyMaterialSeriesCardData card, {
    required bool isWeapon,
  }) {
    final icons = <_NeedIcon>[];
    final seen = <String>{};

    void add(String id, String name, String? iconUrl) {
      if (id.isEmpty || !seen.add(id)) return;
      icons.add(_NeedIcon(id: id, name: name, iconUrl: iconUrl));
    }

    for (final group in card.consumerGroups) {
      for (final consumer in group.consumers) {
        if (!consumer.hasShortage) continue;
        if (isWeapon) {
          if (consumer.equippedCharacters.isNotEmpty) {
            for (final eq in consumer.equippedCharacters) {
              add(eq.id, eq.name, eq.iconUrl);
            }
          } else {
            add(consumer.id, consumer.name, consumer.iconUrl);
          }
        } else {
          add(consumer.id, consumer.name, consumer.iconUrl);
        }
      }
    }
    return icons;
  }

  Widget _closedSummary(List<_NeedIcon> icons) {
    if (icons.isEmpty) {
      return const Text('不足なし');
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final icon in icons.take(12))
          Tooltip(
            message: icon.name,
            child: GameIconImage(
              iconUrl: icon.iconUrl,
              size: 28,
              borderRadius: 6,
              fallback: Text(
                icon.name.isNotEmpty ? icon.name[0] : '?',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        if (icons.length > 12)
          Text(
            '+${icons.length - 12}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planAsync = ref.watch(dailyMaterialsPlanProvider(_selectedWeekday));
    final isToday = _selectedWeekday == _todayWeekday;
    final isWeapon = _viewKind == _DailyMaterialViewKind.weapon;

    return Scaffold(
      appBar: AppBar(
        title: const Text('曜日素材'),
        actions: const [ShellMenuButton()],
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
                        day == _todayWeekday
                            ? FontWeight.bold
                            : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(userFacingError(e))),
        data: (plan) {
          final cards = isWeapon ? plan.weaponCards : plan.talentCards;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  isToday
                      ? '今日入手できる素材'
                      : '${weekdayLabelsJa[_selectedWeekday]}曜日に入手できる素材',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownMenu<_DailyMaterialViewKind>(
                  key: ValueKey(_viewKind),
                  initialSelection: _viewKind,
                  label: const Text('表示'),
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(
                      value: _DailyMaterialViewKind.talent,
                      label: '天賦素材',
                    ),
                    DropdownMenuEntry(
                      value: _DailyMaterialViewKind.weapon,
                      label: '武器素材',
                    ),
                  ],
                  onSelected: (value) {
                    if (value == null) return;
                    setState(() => _viewKind = value);
                  },
                ),
                const SizedBox(height: 12),
                if (cards.isEmpty)
                  Text(
                    isWeapon ? 'この曜日の武器突破素材はありません' : 'この曜日の天賦素材はありません',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (final card in cards) ...[
                    DetailSectionAccordion(
                      key: ValueKey(
                        '${_selectedWeekday}_${_viewKind.name}_${card.series.id}',
                      ),
                      title: '「${card.series.name}」· ${card.series.region}',
                      summary: _closedSummary(
                        _needIcons(card, isWeapon: isWeapon),
                      ),
                      defaultOpen: false,
                      child: DailyMaterialSeriesCard(
                        card: card,
                        embedded: true,
                        emptyConsumersLabel: isWeapon ? '使用武器なし' : '使用キャラクターなし',
                        showGroupLabels: isWeapon,
                        onConsumerTap:
                            isWeapon
                                ? null
                                : (id) => context.push('/characters/$id'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NeedIcon {
  const _NeedIcon({required this.id, required this.name, this.iconUrl});

  final String id;
  final String name;
  final String? iconUrl;
}
