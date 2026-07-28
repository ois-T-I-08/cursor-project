import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/amber_detail_models.dart';
import '../../../domain/character_stats.dart';
import '../../../providers/character_detail_providers.dart';
import '../../shared/game_icon_image.dart';

/// Weapon detail bottom sheet
Future<void> showWeaponDetailSheet({
  required BuildContext context,
  required String weaponId,
  required int weaponLevel,
  required int refinement,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (context) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder:
              (context, scrollController) => WeaponDetailSheet(
                weaponId: weaponId,
                weaponLevel: weaponLevel,
                refinement: refinement,
                scrollController: scrollController,
              ),
        ),
  );
}

class WeaponDetailSheet extends ConsumerWidget {
  const WeaponDetailSheet({
    super.key,
    required this.weaponId,
    required this.weaponLevel,
    required this.refinement,
    this.scrollController,
  });

  final String weaponId;
  final int weaponLevel;
  final int refinement;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(weaponDetailProvider(weaponId));
    final theme = Theme.of(context);

    return async.when(
      loading:
          () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
      error:
          (_, __) => const Padding(
            padding: EdgeInsets.all(24),
            child: Text('武器詳細を取得できませんでした'),
          ),
      data: (detail) {
        if (detail == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('武器詳細を取得できませんでした'),
          );
        }
        return _WeaponDetailBody(
          detail: detail,
          weaponLevel: weaponLevel,
          refinement: refinement.clamp(1, 5),
          scrollController: scrollController,
          theme: theme,
        );
      },
    );
  }
}

class _WeaponDetailBody extends StatelessWidget {
  const _WeaponDetailBody({
    required this.detail,
    required this.weaponLevel,
    required this.refinement,
    required this.theme,
    this.scrollController,
  });

  final WeaponDetailData detail;
  final int weaponLevel;
  final int refinement;
  final ThemeData theme;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final levelStats = detail.stats.statsAtLevel(weaponLevel);
    final ascension = _weaponAscension(detail.stats, weaponLevel);
    final subValue = levelStats.subStatValue;
    final subProp = levelStats.subStatProp ?? detail.subStatProp;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            GameIconImage(iconUrl: detail.iconUrl, size: 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(detail.name, style: theme.textTheme.titleLarge),
                  Text(
                    '${detail.rarity}★ · ${detail.weaponTypeLabel}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _kv(theme, 'レベル', 'Lv.$weaponLevel'),
        _kv(theme, '突破段階', '突破 $ascension'),
        _kv(theme, '基礎攻撃力', levelStats.baseAttack.round().toString()),
        if (subProp != null && subValue != null)
          _kv(
            theme,
            'サブステータス',
            '${detail.subStatName ?? fightPropLabel(subProp)} '
                '${formatFightPropValue(subProp, subValue)}',
          ),
        _kv(theme, '精錬ランク', 'R$refinement'),
        if (detail.effectName != null && detail.effectName!.isNotEmpty) ...[
          const Divider(height: 28),
          Text('武器効果', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            detail.effectName!,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          if (detail.effectDescriptions.isEmpty)
            Text('効果説明を取得できませんでした', style: theme.textTheme.bodySmall)
          else ...[
            Text(
              detail.effectDescriptions[(refinement - 1).clamp(
                0,
                detail.effectDescriptions.length - 1,
              )],
              style: theme.textTheme.bodyMedium,
            ),
            if (detail.effectDescriptions.length > 1) ...[
              const SizedBox(height: 16),
              Text('精錬による効果変化', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...List.generate(detail.effectDescriptions.length, (i) {
                final rank = i + 1;
                final selected = rank == refinement;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? theme.colorScheme.primaryContainer.withValues(
                                alpha: 0.45,
                              )
                              : null,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'R$rank${selected ? '（現在）' : ''}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color:
                                  selected ? theme.colorScheme.primary : null,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            detail.effectDescriptions[i],
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ],
      ],
    );
  }

  int _weaponAscension(WeaponStatsData stats, int level) {
    final sorted = [...stats.promotes]
      ..sort((a, b) => a.promoteLevel.compareTo(b.promoteLevel));
    for (final p in sorted) {
      if (p.unlockMaxLevel >= level.clamp(1, 90)) {
        return p.promoteLevel;
      }
    }
    return sorted.isEmpty ? 0 : sorted.last.promoteLevel;
  }

  Widget _kv(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
