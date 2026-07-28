import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/akasha/akasha_weapon_usage.dart';
import '../../../domain/game_display.dart';
import '../../../domain/models/master_models.dart';
import '../../../domain/level_config.dart';
import '../../../domain/weapon_list_sort.dart';
import '../../../providers/character_detail_providers.dart';
import '../../shared/game_icon_image.dart';
import '../../shared/selectable_detail_list_tile.dart';

/// 武器選択ボトムシート。行タップで選択、ⓘ で詳細（変更しない）。
/// 並び替えはシート表示中のみ保持する。
Future<String?> showWeaponPickerSheet({
  required BuildContext context,
  required List<MasterWeapon> weapons,
  required String selectedWeaponId,
  required int equippedWeaponLevel,
  required MasterCharacter character,
  required void Function(MasterWeapon weapon) onShowDetail,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return WeaponPickerSheet(
            weapons: weapons,
            selectedWeaponId: selectedWeaponId,
            equippedWeaponLevel: equippedWeaponLevel,
            character: character,
            onShowDetail: onShowDetail,
            scrollController: scrollController,
          );
        },
      );
    },
  );
}

class WeaponPickerSheet extends ConsumerStatefulWidget {
  const WeaponPickerSheet({
    super.key,
    required this.weapons,
    required this.selectedWeaponId,
    required this.equippedWeaponLevel,
    required this.character,
    required this.onShowDetail,
    this.scrollController,
  });

  final List<MasterWeapon> weapons;
  final String selectedWeaponId;
  final int equippedWeaponLevel;
  final MasterCharacter character;
  final void Function(MasterWeapon weapon) onShowDetail;
  final ScrollController? scrollController;

  @override
  ConsumerState<WeaponPickerSheet> createState() => _WeaponPickerSheetState();
}

class _WeaponPickerSheetState extends ConsumerState<WeaponPickerSheet> {
  WeaponListSortMode _sortMode = WeaponListSortMode.popularity;
  WeaponListFilter _filter = WeaponListFilter.none;
  late List<WeaponListEntry> _entries;
  bool _loadingStats = false;
  WeaponUsageSnapshot? _usage;

  @override
  void initState() {
    super.initState();
    _entries =
        widget.weapons
            .map(
              (w) => WeaponListEntry(
                weapon: w,
                recommendScore: computeWeaponRecommendScore(
                  weapon: w,
                  character: widget.character,
                ),
              ),
            )
            .toList();
    _filter = WeaponListFilter(weaponType: widget.character.weaponType);
    _enrichStats();
    _loadUsageRates();
  }

  List<WeaponListEntry> get _visible => prepareWeaponList(
    entries: _entries,
    sortMode: _sortMode,
    filter: _filter,
    selectedWeaponId: widget.selectedWeaponId,
  );

  void _applyUsageToEntries(WeaponUsageSnapshot usage) {
    _usage = usage;
    final useRemote = usage.isFromRemote && usage.sampleSize > 0;
    _entries =
        _entries.map((entry) {
          if (!useRemote) {
            return entry.copyWith(
              recommendScore: computeWeaponRecommendScore(
                weapon: entry.weapon,
                character: widget.character,
                specialProp: entry.specialProp,
                baseAttack: entry.baseAttack,
              ),
            );
          }
          final rate = usage.rateFor(entry.id);
          return entry.copyWith(
            usageRate: rate,
            recommendScore: computeWeaponPopularityScore(
              usageRate: rate,
              rarity: entry.rarity,
              baseAttack: entry.baseAttack,
            ),
          );
        }).toList();
  }

  Future<void> _loadUsageRates() async {
    try {
      final usage = await ref
          .read(akashaWeaponUsageRepositoryProvider)
          .getUsageRates(widget.character.id);
      if (!mounted) return;
      setState(() => _applyUsageToEntries(usage));
    } catch (_) {
      // 失敗時はローカル推定のまま
    }
  }

  Future<void> _enrichStats() async {
    if (!mounted) return;
    setState(() => _loadingStats = true);
    final repo = ref.read(amberDetailRepositoryProvider);
    const concurrency = 4;
    final source = [..._entries];
    final next = List<WeaponListEntry>.from(source);

    Future<void> enrichAt(int index) async {
      final entry = source[index];
      try {
        final detail = await repo.getWeaponDetail(entry.weapon.id);
        if (detail == null) return;
        final atk = detail.stats.statsAtLevel(levelMax).baseAttack;
        final special = detail.subStatProp;
        final usage = _usage;
        final useRemote =
            usage != null && usage.isFromRemote && usage.sampleSize > 0;
        if (useRemote) {
          final rate = usage.rateFor(entry.id);
          next[index] = entry.copyWith(
            baseAttack: atk,
            specialProp: special,
            usageRate: rate,
            recommendScore: computeWeaponPopularityScore(
              usageRate: rate,
              rarity: entry.rarity,
              baseAttack: atk,
            ),
          );
        } else {
          next[index] = entry.copyWith(
            baseAttack: atk,
            specialProp: special,
            recommendScore: computeWeaponRecommendScore(
              weapon: entry.weapon,
              character: widget.character,
              specialProp: special,
              baseAttack: atk,
            ),
          );
        }
      } catch (_) {
        // 個別失敗はスキップ
      }
    }

    for (var i = 0; i < source.length; i += concurrency) {
      final end = (i + concurrency).clamp(0, source.length);
      await Future.wait([for (var j = i; j < end; j++) enrichAt(j)]);
      if (!mounted) return;
      setState(() {
        _entries = List<WeaponListEntry>.from(next);
        final usage = _usage;
        if (usage != null) _applyUsageToEntries(usage);
      });
    }

    if (!mounted) return;
    setState(() {
      final usage = _usage;
      if (usage != null) _applyUsageToEntries(usage);
      _loadingStats = false;
    });
  }

  String? get _usageCaption {
    final usage = _usage;
    if (usage == null) return null;
    if (usage.isFromRemote && usage.sampleSize > 0) {
      return '使用率: Akasha 公開ビルド集計（n=${usage.sampleSize}）';
    }
    return '使用率取得失敗のためローカル推定を表示';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;
    final caption = _usageCaption;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text('武器を選択', style: theme.textTheme.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            '行をタップで装備変更、ⓘ で詳細（変更しません）',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '並び替え',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<WeaponListSortMode>(
                      isExpanded: true,
                      isDense: true,
                      value: _sortMode,
                      items:
                          WeaponListSortMode.values
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m.label),
                                ),
                              )
                              .toList(),
                      onChanged: (mode) {
                        if (mode == null) return;
                        setState(() => _sortMode = mode);
                      },
                    ),
                  ),
                ),
              ),
              if (_loadingStats) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
        if (caption != null && _sortMode == WeaponListSortMode.popularity)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              caption,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            controller: widget.scrollController,
            itemCount: visible.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = visible[index];
              final weapon = entry.weapon;
              final equipped = weapon.id == widget.selectedWeaponId;
              final typeLabel =
                  weaponTypeLabelMap[weapon.weaponType] ?? weapon.weaponType;
              final levelLabel =
                  equipped
                      ? 'Lv.${widget.equippedWeaponLevel}'
                      : 'Lv.$levelMax';
              final atkLabel =
                  entry.baseAttack > 0
                      ? ' · 基礎ATK ${entry.baseAttack.round()}'
                      : '';
              final usageLabel =
                  _sortMode == WeaponListSortMode.popularity &&
                          entry.usageRate != null &&
                          (_usage?.isFromRemote ?? false)
                      ? ' · 使用率 ${(entry.usageRate! * 100).toStringAsFixed(1)}%'
                      : '';

              return SelectableDetailListTile(
                leading: GameIconImage(iconUrl: weapon.iconUrl, size: 40),
                title: weapon.name,
                subtitle:
                    '$levelLabel · ${weapon.rarity}★ · $typeLabel$atkLabel$usageLabel',
                isEquipped: equipped,
                onSelect: () => Navigator.of(context).pop(weapon.id),
                onDetail: () => widget.onShowDetail(weapon),
              );
            },
          ),
        ),
      ],
    );
  }
}
