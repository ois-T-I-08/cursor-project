import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/growth_providers.dart';
import '../../../providers/app_providers.dart';
import '../../../domain/history/growth_event.dart';

/// Growth timeline screen.
class GrowthTimelineScreen extends ConsumerStatefulWidget {
  const GrowthTimelineScreen({super.key});
  @override
  ConsumerState<GrowthTimelineScreen> createState() => _GrowthTimelineScreenState();
}

class _GrowthTimelineScreenState extends ConsumerState<GrowthTimelineScreen> {
  final _scrollCtrl = ScrollController();
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    try {
      final repo = await ref.read(growthEventRepoProvider.future);
      final userId = await ref.read(localUserIdProvider.future);
      final initial = ref.read(growthTimelineProvider).value ?? const [];
      final current = _allEvents.isEmpty ? initial : _allEvents;
      GrowthEventCursor? cursor;
      if (current.isNotEmpty) {
        final last = current.last;
        cursor = GrowthEventCursor(
          observedAt: last.observedAt,
          eventId: last.eventId,
        );
      }
      final more = await repo.getByUser(userId, limit: 50, cursor: cursor);
      if (!mounted) return;
      setState(() {
        if (_allEvents.isEmpty) _allEvents.addAll(initial);
        final ids = {for (final e in _allEvents) e.eventId};
        for (final e in more) {
          if (ids.add(e.eventId)) _allEvents.add(e);
        }
        _hasMore = more.length == 50;
      });
    } finally {
      _loadingMore = false;
    }
  }

  final List<GrowthEvent> _allEvents = [];

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _eventLabel(GrowthEvent e) {
    final before = e.beforeValue ?? '?';
    final after = e.afterValue ?? '?';
    switch (e.eventType) {
      case GrowthEventType.characterLevelChanged: return '\u30ad\u30e3\u30e9\u30ec\u30d9\u30eb $before \u2192 $after';
      case GrowthEventType.ascensionChanged: return '\u7a81\u7834 $before \u2192 $after';
      case GrowthEventType.talentNormalChanged: return '\u901a\u5e38\u653b\u6483 $before \u2192 $after';
      case GrowthEventType.talentSkillChanged: return '\u5143\u7d20\u30b9\u30ad\u30eb $before \u2192 $after';
      case GrowthEventType.talentBurstChanged: return '\u5143\u7d20\u7206\u767a $before \u2192 $after';
      case GrowthEventType.weaponChanged: return '\u6b66\u5668\u5909\u66f4';
      case GrowthEventType.weaponLevelChanged: return '\u6b66\u5668\u30ec\u30d9\u30eb $before \u2192 $after';
      case GrowthEventType.weaponRefinementChanged: return '\u6b66\u5668\u7cbe\u934b $before \u2192 $after';
      case GrowthEventType.artifactCompletionChanged: return '\u8056\u907a\u7269\u5b8c\u6210\u5ea6 $before \u2192 $after';
      case GrowthEventType.growthGoalCompleted: return '\u80b2\u6210\u76ee\u6a19\u9054\u6210';
      case GrowthEventType.teamCompleted: return '\u7de8\u6210\u5b8c\u6210';
      case GrowthEventType.accountHealthScoreChanged: return '\u30a2\u30ab\u30a6\u30f3\u30c8\u5065\u5eb7\u8a3a\u65ad';
    }
  }

  @override
  Widget build(BuildContext context) {
    final timelineAsync = ref.watch(growthTimelineProvider);
    final charactersAsync = ref.watch(charactersProvider);
    final theme = Theme.of(context);
    final nameById = <String, String>{
      for (final c in charactersAsync.valueOrNull ?? const []) c.id: c.name,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('成長タイムライン')),
      body: timelineAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('読み込みエラー')),
        data: (events) {
          if (events.isEmpty) {
            return Center(
              child: Text('育成履歴はまだありません。', style: theme.textTheme.bodyLarge),
            );
          }
          final all = _allEvents.isEmpty ? events : _allEvents;
          final grouped = <String, List<GrowthEvent>>{};
          for (final e in all) {
            final date = '${e.observedAt.year}/${e.observedAt.month}/${e.observedAt.day}';
            grouped.putIfAbsent(date, () => []).add(e);
          }

          return ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            itemCount: grouped.length + (_hasMore ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i >= grouped.length) {
                return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
              }
              final date = grouped.keys.elementAt(i);
              final dayEvents = grouped[date]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(date, style: theme.textTheme.titleSmall),
                  ),
                  ...dayEvents.map((e) {
                    final name = e.characterId.isEmpty
                        ? '（全体）'
                        : (nameById[e.characterId] ?? e.characterId);
                    return Card(
                      child: ListTile(
                        dense: true,
                        title: Text(name, style: theme.textTheme.labelSmall),
                        subtitle: Text(_eventLabel(e)),
                      ),
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
