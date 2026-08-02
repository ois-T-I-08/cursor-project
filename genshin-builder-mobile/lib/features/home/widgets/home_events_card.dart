import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/user_facing_error.dart';
import '../../../domain/gacha/calendar_event.dart';
import '../../../providers/gacha_providers.dart';
import '../../shared/game_icon_image.dart';

/// ホーム用: 開催中・予告イベント（ennead calendar）
class HomeEventsCard extends ConsumerWidget {
  const HomeEventsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(homeCalendarEventsProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('開催中のイベント', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '更新',
                  onPressed: () => ref.invalidate(homeCalendarEventsProvider),
                ),
              ],
            ),
            const SizedBox(height: 8),
            async.when(
              loading:
                  () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              error:
                  (e, _) => Text(
                    userFacingError(e),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
              data: (events) {
                if (events.isEmpty) {
                  return Text(
                    '表示できるイベントはありません',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                final shown = events.take(5).toList();
                return Column(
                  children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0) const Divider(height: 16),
                      _EventTile(event: shown[i]),
                    ],
                    if (events.length > shown.length) ...[
                      const SizedBox(height: 8),
                      Text(
                        '他 ${events.length - shown.length} 件',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    final active = event.isActiveAt(now);
    final dateFormat = DateFormat('M/d HH:mm');
    CalendarEventReward? reward = event.specialReward;
    if (reward == null) {
      for (final r in event.rewards) {
        if ((r.amount ?? 0) > 0) {
          reward = r;
          break;
        }
      }
      reward ??= event.rewards.isEmpty ? null : event.rewards.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (active)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 2),
                child: Chip(
                  label: const Text('開催中'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  labelStyle: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: theme.colorScheme.primaryContainer,
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(right: 8, top: 2),
                child: Chip(
                  label: Text('予告'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  labelStyle: TextStyle(fontSize: 11),
                ),
              ),
            Expanded(
              child: Text(
                event.name,
                style: theme.textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${dateFormat.format(event.start.toLocal())} 〜 '
          '${dateFormat.format(event.end.toLocal())}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (event.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            event.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (reward != null && reward.name.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              GameIconImage(
                iconUrl: reward.icon,
                size: 28,
                borderRadius: 4,
                fallback: const Icon(Icons.card_giftcard, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reward.amount != null && reward.amount! > 0
                      ? '${reward.name} ×${reward.amount}'
                      : reward.name,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
