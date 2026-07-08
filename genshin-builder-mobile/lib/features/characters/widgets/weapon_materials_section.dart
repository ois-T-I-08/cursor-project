import 'package:flutter/material.dart';

import '../../../data/models/master_models.dart';
import '../../../domain/bookmark_utils.dart';
import '../../../domain/level_progression.dart';
import '../../../domain/material_requirements.dart';
import '../../../domain/models/bookmark.dart';
import '../../../domain/models/calculation_models.dart';
import '../../shared/mark_slider.dart';
import '../../shared/material_list_tile.dart';

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

  bool _isBookmarked(String sourceKey, String materialId) =>
      isMaterialBookmarked(bookmarks, sourceKey, materialId);

  @override
  Widget build(BuildContext context) {
    final selected =
        weapons.where((w) => w.id == selectedWeaponId).firstOrNull;

    final nextStage = promotes.isEmpty
        ? null
        : getNextStageRequirements(
            weaponLevel,
            promotes,
            'weapon',
            weaponRarity,
          );

    final rangeLines = promotes.isEmpty
        ? <RequirementLine>[]
        : getRangeLevelRequirements(
            weaponLevel,
            targetWeaponLevel,
            promotes,
            'weapon',
            weaponRarity: weaponRarity,
            resolveName: resolveName,
          );

    final rangeSourceKey =
        makeRangeSourceKey(bookmarkContext, weaponLevel, targetWeaponLevel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('武器', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        DropdownButton<String?>(
          isExpanded: true,
          value: selectedWeaponId.isEmpty ? null : selectedWeaponId,
          hint: const Text('武器を選択'),
          items: [
            ...weapons.map(
              (w) => DropdownMenuItem(
                value: w.id,
                child: Text('${w.name} (${w.rarity}★)'),
              ),
            ),
          ],
          onChanged: onWeaponSelected,
        ),
        if (selected != null) ...[
          const SizedBox(height: 16),
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
            headerTrailing: rangeLines.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.bookmark_add_outlined),
                    tooltip: '範囲をブックマーク',
                    onPressed: () =>
                        onBookmarkRange(rangeLines, rangeSourceKey),
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
              ).map(
                (line) {
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
                },
              ),
            const Divider(height: 24),
            Text('目標までの合計', style: Theme.of(context).textTheme.titleMedium),
            if (rangeLines.isEmpty)
              const Text('目標レベルを現在より上に設定してください')
            else
              ...rangeLines.map(
                (line) => MaterialListTile(
                  line: line,
                  isBookmarked:
                      _isBookmarked(rangeSourceKey, line.materialId),
                  onToggleBookmark: () =>
                      onToggleRangeBookmark(line, rangeSourceKey),
                ),
              ),
          ],
        ],
      ],
    );
  }
}
