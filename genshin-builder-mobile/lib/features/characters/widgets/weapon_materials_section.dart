import 'package:flutter/material.dart';

import '../../../domain/models/master_models.dart';
import '../../../domain/game_display.dart';
import '../../../domain/bookmark_utils.dart';
import '../../../domain/level_config.dart';
import '../../../domain/level_progression.dart';
import '../../../domain/material_requirements.dart';
import '../../../domain/models/bookmark.dart';
import '../../../domain/models/calculation_models.dart';
import '../../shared/game_icon_image.dart';
import '../../shared/mark_slider.dart';
import '../../shared/material_list_tile.dart';
import '../../shared/max_enhanced_banner.dart';
import 'weapon_picker_sheet.dart';

/// 武器レベル・突破素材（Web `WeaponSection` / `LevelMaterialsPanel` 相当）
class WeaponMaterialsSection extends StatelessWidget {
  const WeaponMaterialsSection({
    super.key,
    required this.weapons,
    required this.selectedWeaponId,
    required this.weaponLevel,
    required this.targetWeaponLevel,
    required this.promotes,
    required this.weaponRarity,
    required this.bookmarkContext,
    required this.bookmarks,
    required this.resolveName,
    required this.resolveIcon,
    required this.onWeaponSelected,
    required this.onWeaponLevelChanged,
    required this.onTargetWeaponLevelChanged,
    required this.onToggleBookmark,
    required this.onToggleRangeBookmark,
    required this.onBookmarkRange,
    this.showTitle = true,
    this.allowedWeaponType,
    this.onShowWeaponDetail,
    this.equippedRefinement = 1,
    this.character,
  });

  final List<MasterWeapon> weapons;
  final String selectedWeaponId;
  final int weaponLevel;
  final int targetWeaponLevel;
  final List<PromoteStage> promotes;
  final int weaponRarity;
  final CultivationBookmarkContext bookmarkContext;
  final List<MaterialBookmarkEntry> bookmarks;
  final String Function(String id) resolveName;
  final String? Function(String id) resolveIcon;
  final ValueChanged<String?> onWeaponSelected;
  final ValueChanged<int> onWeaponLevelChanged;
  final ValueChanged<int> onTargetWeaponLevelChanged;
  final void Function(RequirementLine line, String scope) onToggleBookmark;
  final void Function(RequirementLine line, String rangeSourceKey)
  onToggleRangeBookmark;
  final void Function(List<RequirementLine> lines, String sourceKey)
  onBookmarkRange;
  final bool showTitle;

  /// キャラクターの装備可能武器種（例: sword）。指定時はこの種のみ表示
  final String? allowedWeaponType;

  /// 武器詳細表示（選択変更とは分離）
  final void Function(MasterWeapon weapon, {required bool isEquipped})?
  onShowWeaponDetail;

  final int equippedRefinement;

  /// 人気順（使用率）並び替え用
  final MasterCharacter? character;

  bool _isBookmarked(String sourceKey, String materialId) =>
      isMaterialBookmarked(bookmarks, sourceKey, materialId);

  Future<void> _openPicker(
    BuildContext context,
    List<MasterWeapon> filtered,
  ) async {
    final character = this.character;
    if (character == null) return;
    final picked = await showWeaponPickerSheet(
      context: context,
      weapons: filtered,
      selectedWeaponId: selectedWeaponId,
      equippedWeaponLevel: weaponLevel,
      character: character,
      onShowDetail: (weapon) {
        final equipped = weapon.id == selectedWeaponId;
        onShowWeaponDetail?.call(weapon, isEquipped: equipped);
      },
    );
    if (picked != null) {
      onWeaponSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        allowedWeaponType == null
            ? weapons
            : weapons.where((w) => w.weaponType == allowedWeaponType).toList();
    final selected = weapons.where((w) => w.id == selectedWeaponId).firstOrNull;

    final nextStage =
        promotes.isEmpty
            ? null
            : getNextStageRequirements(
              weaponLevel,
              promotes,
              'weapon',
              weaponRarity,
            );

    final rangeLines =
        promotes.isEmpty
            ? <RequirementLine>[]
            : getRangeLevelRequirements(
              weaponLevel,
              targetWeaponLevel,
              promotes,
              'weapon',
              weaponRarity: weaponRarity,
              resolveName: resolveName,
              resolveIcon: resolveIcon,
            );

    final rangeSourceKey = makeRangeSourceKey(
      bookmarkContext,
      weaponLevel,
      targetWeaponLevel,
    );

    final typeLabel =
        allowedWeaponType == null
            ? null
            : (weaponTypeLabelMap[allowedWeaponType!] ?? allowedWeaponType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) ...[
          Text('武器', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
        ],
        if (typeLabel != null) ...[
          Text(
            '装備可能: $typeLabelのみ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton(
          onPressed:
              filtered.isEmpty ? null : () => _openPicker(context, filtered),
          child: Row(
            children: [
              if (selected != null) ...[
                GameIconImage(iconUrl: selected.iconUrl, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(selected.name, overflow: TextOverflow.ellipsis),
                ),
              ] else
                const Expanded(child: Text('武器を選択')),
              const Icon(Icons.expand_more),
            ],
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              GameIconImage(iconUrl: selected.iconUrl, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${selected.rarity}★ · Lv.$weaponLevel · 装備中',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onShowWeaponDetail != null)
                IconButton(
                  tooltip: '詳細',
                  icon: const Icon(Icons.info_outline),
                  onPressed:
                      () => onShowWeaponDetail!(selected, isEquipped: true),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (weaponLevel >= levelMax) ...[
            MaxEnhancedBanner(label: '武器レベル', level: weaponLevel),
            const SizedBox(height: 8),
            LevelMarkSlider(
              label: '武器レベル（シミュレーション）',
              value: weaponLevel,
              onChanged: onWeaponLevelChanged,
            ),
          ] else ...[
            LevelMarkSlider(
              label: '武器レベル',
              value: weaponLevel,
              onChanged: onWeaponLevelChanged,
            ),
            const SizedBox(height: 16),
            LevelMarkSlider(
              label: '目標レベル',
              value: targetWeaponLevel,
              onChanged: onTargetWeaponLevelChanged,
              headerTrailing:
                  rangeLines.isEmpty
                      ? null
                      : IconButton(
                        icon: const Icon(Icons.bookmark_add_outlined),
                        tooltip: '範囲をブックマーク',
                        onPressed:
                            () => onBookmarkRange(rangeLines, rangeSourceKey),
                      ),
            ),
            if (promotes.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '突破データ未取得 — 設定でマスタ同期を実行してください',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ] else ...[
              const Divider(height: 32),
              Text('次の段階', style: Theme.of(context).textTheme.titleMedium),
              if (nextStage == null)
                const Text('最大レベルです')
              else
                ...nextStageToRequirementLines(
                  nextStage.materials,
                  nextStage.levelUpMaterials,
                  nextStage.mora,
                  resolveName,
                  resolveIcon: resolveIcon,
                ).map((line) {
                  final sourceKey = makeItemSourceKey(
                    bookmarkContext,
                    'next',
                    line.materialId,
                  );
                  return MaterialListTile(
                    line: line,
                    isBookmarked: _isBookmarked(sourceKey, line.materialId),
                    onToggleBookmark: () => onToggleBookmark(line, 'next'),
                  );
                }),
              const Divider(height: 24),
              Text('目標までの合計', style: Theme.of(context).textTheme.titleMedium),
              if (rangeLines.isEmpty)
                const Text('目標レベルを現在より上に設定してください')
              else
                ...rangeLines.map(
                  (line) => MaterialListTile(
                    line: line,
                    isBookmarked: _isBookmarked(
                      rangeSourceKey,
                      line.materialId,
                    ),
                    onToggleBookmark:
                        () => onToggleRangeBookmark(line, rangeSourceKey),
                  ),
                ),
            ],
          ],
        ],
      ],
    );
  }
}
