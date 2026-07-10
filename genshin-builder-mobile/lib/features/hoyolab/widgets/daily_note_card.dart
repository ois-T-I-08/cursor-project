import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/hoyolab/models/daily_note.dart';
import '../../../core/errors/user_facing_error.dart';
import '../../../providers/hoyolab_home_providers.dart';
import '../../../providers/hoyolab_providers.dart';

class DailyNoteCard extends ConsumerWidget {
  const DailyNoteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagsAsync = ref.watch(featureFlagsProvider);
    final sessionAsync = ref.watch(hoyolabSessionProvider);
    final dailyAsync = ref.watch(dailyNoteProvider);

    return flagsAsync.when(
      data: (flags) {
        if (!flags.hoyolabLinkEnabled) {
          return const _DisabledCard();
        }
        return sessionAsync.when(
          data: (session) {
            if (!session.isLinked) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.link_off),
                  title: const Text('HoYoLAB 未連携'),
                  subtitle: const Text('設定から HoYoLAB と連携すると樹脂等を表示できます'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/settings/hoyolab'),
                ),
              );
            }
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'リアルタイムメモ',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: '更新',
                          onPressed: () =>
                              ref.read(dailyNoteProvider.notifier).refresh(),
                        ),
                        TextButton(
                          onPressed: () => context.go('/settings/hoyolab'),
                          child: const Text('設定'),
                        ),
                      ],
                    ),
                    if (session.nickname != null)
                      Text(
                        '${session.nickname} (UID ${session.uid})',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 12),
                    dailyAsync.when(
                      data: (note) {
                        if (note == null) {
                          return const Text('データを取得できませんでした。設定を確認してください。');
                        }
                        return _DailyNoteBody(note: note);
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Text(userFacingError(e)),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (e, _) => Text(userFacingError(e, fallback: 'セッションの読み込みに失敗しました。')),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text(userFacingError(e)),
    );
  }
}

class _DisabledCard extends StatelessWidget {
  const _DisabledCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.block),
        title: Text('HoYoLAB 連携は無効です'),
        subtitle: Text('機能フラグにより停止中です'),
      ),
    );
  }
}

class _DailyNoteBody extends StatelessWidget {
  const _DailyNoteBody({required this.note});

  final DailyNote note;

  String _formatRecovery(String secondsRaw) {
    final seconds = int.tryParse(secondsRaw) ?? 0;
    if (seconds <= 0) return '全回復済み';
    final duration = Duration(seconds: seconds);
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    return '$h時間$m分で1回復';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatRow(
          icon: Icons.water_drop_outlined,
          label: '天然樹脂',
          value: '${note.currentResin} / ${note.maxResin}',
          sub: note.remainingResin > 0
              ? _formatRecovery(note.resinRecoveryTime)
              : '満タン',
        ),
        const SizedBox(height: 8),
        _StatRow(
          icon: Icons.task_alt,
          label: 'デイリー任務',
          value: '${note.finishedTaskNum} / ${note.totalTaskNum}',
          sub: note.dailyTasksComplete ? '完了' : '未完了あり',
        ),
        const SizedBox(height: 8),
        _StatRow(
          icon: Icons.explore_outlined,
          label: '探索派遣',
          value:
              '完了 ${note.finishedExpeditions} / 進行中 ${note.activeExpeditions}',
          sub: note.expeditions.isEmpty ? '派遣なし' : '合計 ${note.expeditions.length}',
        ),
        const SizedBox(height: 8),
        _StatRow(
          icon: Icons.home_outlined,
          label: '洞天宝錢',
          value: '${note.currentHomeCoin} / ${note.maxHomeCoin}',
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleSmall),
            if (sub != null)
              Text(sub!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}
