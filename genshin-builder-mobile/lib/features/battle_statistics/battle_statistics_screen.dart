import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors/user_facing_error.dart';
import '../../domain/models/master_models.dart';
import '../../providers/app_providers.dart';
import '../../providers/battle_statistics_providers.dart';
import '../shared/game_icon_image.dart';
import '../shared/shell_menu_button.dart';

/// YShelper / Neon 由来の編成・キャラクター使用率（AZA 深境螺旋統計とは別）。
class BattleStatisticsScreen extends ConsumerStatefulWidget {
  const BattleStatisticsScreen({super.key});

  @override
  ConsumerState<BattleStatisticsScreen> createState() =>
      _BattleStatisticsScreenState();
}

class _BattleStatisticsScreenState
    extends ConsumerState<BattleStatisticsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      ref.invalidate(battleStatisticsStartupSyncProvider);
      await ref.read(battleStatisticsStartupSyncProvider.future);
      ref.invalidate(battleStatisticsBrowseProvider);
    } catch (_) {
      // Offline / failure: keep local Drift cache visible.
      ref.invalidate(battleStatisticsBrowseProvider);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final browse = ref.watch(battleStatisticsBrowseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('編成使用率統計'),
        actions: [
          IconButton(
            tooltip: '再取得',
            onPressed: _refreshing ? null : _refresh,
            icon:
                _refreshing
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.refresh),
          ),
          const ShellMenuButton(),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '深境螺旋'),
            Tab(text: '幽境の激戦'),
          ],
        ),
      ),
      body: browse.when(
        loading:
            () => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('統計データを読み込んでいます…'),
                ],
              ),
            ),
        error:
            (error, _) => _MessagePane(
              icon: Icons.cloud_off_outlined,
              message: userFacingError(error),
              actionLabel: '再試行',
              onAction: _refresh,
            ),
        data: (pages) {
          if (!pages.enabled) {
            return const _MessagePane(
              icon: Icons.link_off,
              message: 'バックエンド接続先が未設定です。',
            );
          }
          return TabBarView(
            controller: _tabs,
            children: [
              _ContentPane(
                page: pages.abyss,
                onRefresh: _refresh,
                refreshing: _refreshing,
              ),
              _ContentPane(
                page: pages.stygian,
                onRefresh: _refresh,
                refreshing: _refreshing,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ContentPane extends ConsumerWidget {
  const _ContentPane({
    required this.page,
    required this.onRefresh,
    required this.refreshing,
  });

  final BattleStatisticsBrowsePage? page;
  final Future<void> Function() onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (page == null) {
      return _MessagePane(
        icon: Icons.inbox_outlined,
        message: '統計データはまだありません。',
        actionLabel: refreshing ? null : '再取得',
        onAction: refreshing ? null : onRefresh,
      );
    }
    final masters = ref.watch(charactersProvider);
    final byId = <String, MasterCharacter>{
      for (final character in masters.valueOrNull ?? const <MasterCharacter>[])
        character.id: character,
    };
    final percent = NumberFormat.percentPattern('ja');
    final dateFormat = DateFormat.yMMMd('ja').add_Hm();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (page!.isStale)
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: const ListTile(
                leading: Icon(Icons.schedule),
                title: Text('データが古い可能性があります'),
                subtitle: Text('前回の正常データを表示しています。再取得を試してください。'),
              ),
            ),
          if (page!.isOffline)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const ListTile(
                leading: Icon(Icons.wifi_off),
                title: Text('オフライン'),
                subtitle: Text('端末内キャッシュを表示しています。'),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('対象期間: ${page!.seasonId}'),
            subtitle: Text(
              '最終更新: ${dateFormat.format(page!.sourceUpdatedAt.toLocal())}\n'
              '最終取得: ${dateFormat.format(page!.syncedAt.toLocal())}\n'
              'データソース: YShelper（参考統計）\n'
              'サンプル数: ${page!.sampleSize?.toString() ?? '—'}',
            ),
          ),
          const SizedBox(height: 8),
          Text('キャラクター使用率', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...page!.characters.take(40).map((usage) {
            final master = byId[usage.characterId];
            final name = master?.name ?? '不明なキャラクター';
            return ListTile(
              leading: GameIconImage(
                iconUrl: master?.iconUrl,
                size: 40,
                fallback: Text(name.isEmpty ? '?' : name.substring(0, 1)),
              ),
              title: Text(name),
              subtitle: Text(
                [
                  '使用率 ${percent.format(usage.usageRate)}',
                  if (usage.ownershipRate != null)
                    '所持率 ${percent.format(usage.ownershipRate!)}',
                  if (usage.usageAmongOwnersRate != null)
                    '所持者内 ${percent.format(usage.usageAmongOwnersRate!)}',
                  if (usage.side != null) '区分 ${_sideLabel(usage.side!)}',
                ].join(' · '),
              ),
            );
          }),
          const SizedBox(height: 16),
          Text('編成使用率', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...page!.teams.take(30).map((team) {
            final names = team.members
                .map((id) => byId[id]?.name ?? '不明')
                .join(' / ');
            return ListTile(
              title: Text(names),
              subtitle: Text(
                [
                  '使用率 ${percent.format(team.usageRate)}',
                  if (team.side != null) _sideLabel(team.side!),
                  if (team.stageKey != null) team.stageKey!,
                  if (team.sampleSize != null) 'n=${team.sampleSize}',
                ].join(' · '),
              ),
            );
          }),
          const SizedBox(height: 24),
          Text(
            '本データは集計上の参考値です。強さや最適編成を保証するものではありません。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MessagePane extends StatelessWidget {
  const _MessagePane({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => onAction!(),
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _sideLabel(String side) => switch (side) {
  'upper' => '上半',
  'middle' => '中間',
  'lower' => '下半',
  _ => side,
};
