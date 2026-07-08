import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/hoyolab/hoyolab_exceptions.dart';
import '../../../providers/hoyolab_game_providers.dart';
import '../../../providers/hoyolab_game_refresh.dart';

class HoyolabCharacterStatusCard extends ConsumerWidget {
  const HoyolabCharacterStatusCard({
    super.key,
    required this.characterId,
  });

  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buildAsync = ref.watch(hoyolabCharacterBuildProvider(characterId));

    return buildAsync.when(
      data: (build) {
        if (build == null || !build.isOwned) return const SizedBox.shrink();
        final fetchedLabel = build.fetchedAt == null
            ? null
            : formatRelativeUpdateTime(build.fetchedAt!);

        return Card(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(
                alpha: 0.35,
              ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_sync),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'HoYoLAB 実データ',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: '再取得',
                      onPressed: () =>
                          refreshHoyolabCharacterBuild(ref, characterId),
                    ),
                  ],
                ),
                if (fetchedLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '取得 $fetchedLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _Chip(label: 'Lv.${build.level}'),
                    if (build.promoteLevel > 0)
                      _Chip(label: '突破 ${build.promoteLevel}'),
                    if (build.friendship > 0)
                      _Chip(label: '好感度 ${build.friendship}'),
                    if (build.constellation > 0)
                      _Chip(label: '凸 ${build.constellation}'),
                  ],
                ),
                if (build.stats.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('ステータス', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  ...build.stats.take(8).map(
                        (s) => _StatLine(label: s.label, value: s.value),
                      ),
                ],
                if (build.talents.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('天賦', style: Theme.of(context).textTheme.labelLarge),
                  ...build.talents.map(
                    (t) => _StatLine(label: t.name, value: 'Lv.${t.level}'),
                  ),
                ],
                if (build.weapon != null && build.weapon!.name.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('武器', style: Theme.of(context).textTheme.labelLarge),
                  _StatLine(
                    label: build.weapon!.name,
                    value:
                        'Lv.${build.weapon!.level} · R${build.weapon!.refinement}',
                  ),
                  if (build.weapon!.mainStat != null)
                    _StatLine(
                      label: 'メイン',
                      value:
                          '${build.weapon!.mainStat!.label} ${build.weapon!.mainStat!.value}',
                    ),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('HoYoLAB データを取得中…'),
            ],
          ),
        ),
      ),
      error: (e, _) {
        if (e is HoyolabApiException) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('HoYoLAB ステータスを取得できません'),
              subtitle: Text(e.userMessage),
              trailing: TextButton(
                onPressed: () => context.go('/settings/hoyolab'),
                child: const Text('設定'),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
