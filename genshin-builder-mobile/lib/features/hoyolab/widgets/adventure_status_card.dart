import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/hoyolab/hoyolab_exceptions.dart';
import '../../../providers/hoyolab_game_refresh.dart';
import '../../../providers/hoyolab_home_providers.dart';
import '../../../providers/hoyolab_home_providers.dart';

class AdventureStatusCard extends ConsumerWidget {
  const AdventureStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(hoyolabAdventureStatusProvider);

    return statusAsync.when(
      data: (status) {
        if (status == null) return const SizedBox.shrink();
        final spiral = status.spiralAbyss;
        final theater = status.imaginariumTheater;
        if (spiral == null && theater == null) return const SizedBox.shrink();

        final updated = status.latestUpdate;
        final updatedLabel = updated == null
            ? null
            : formatRelativeUpdateTime(updated);

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_stories_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '冒険状況',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: '更新',
                      onPressed: () => refreshHoyolabAdventureStatus(ref),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (spiral != null)
                  _StatusTile(
                    icon: Icons.whatshot_outlined,
                    title: '深境螺旋',
                    value: spiral.isUnlocked
                        ? '${spiral.maxFloor} · ☆${spiral.totalStars}'
                        : '未解放',
                    subtitle: spiral.isUnlocked ? '当期' : null,
                  ),
                if (theater != null) ...[
                  if (spiral != null) const SizedBox(height: 8),
                  _StatusTile(
                    icon: Icons.theater_comedy_outlined,
                    title: '幻想シアター',
                    value: theater.hasData
                        ? '${theater.difficultyLabel} · 第${theater.maxRoundId}幕'
                        : theater.isUnlocked
                            ? 'データなし'
                            : '未解放',
                    subtitle: theater.medalNum > 0
                        ? 'メダル ${theater.medalNum}'
                        : null,
                  ),
                ],
                if (updatedLabel != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '最終更新 $updatedLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) {
        if (e is HoyolabApiException) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('冒険状況を取得できません'),
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

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
