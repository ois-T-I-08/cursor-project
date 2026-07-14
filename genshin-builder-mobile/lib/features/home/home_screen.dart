import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/app_providers.dart';
import '../../providers/background_master_repair_provider.dart';
import '../../providers/daily_materials_providers.dart';
import '../../providers/hoyolab_home_providers.dart';
import '../../providers/hoyolab_providers.dart';
import '../../providers/growth_providers.dart';
import '../../domain/team/main_tab.dart';
import '../../router.dart';
import '../../core/errors/user_facing_error.dart';
import '../../widgets/deferred_loader.dart';
import '../hoyolab/widgets/adventure_status_card.dart';
import '../hoyolab/widgets/daily_note_card.dart';
import '../shared/shell_menu_button.dart';
import 'widgets/home_events_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final repair = ref.read(backgroundMasterRepairProvider);
      // 描画を await しない
      unawaited(repair.ensureStartedAfterHome());
      repair.ensureHoyolabPrefetch(() => prefetchHoyolabHomeData(ref));
    });
  }

  @override
  Widget build(BuildContext context) {
    // 副作用のみ: watch だと Future 完了でホーム全体が再ビルドされる
    ref.listen(dailyProgressPrefetchProvider, (_, __) {});

    final lastSyncAsync = ref.watch(lastSyncTimeProvider);
    final numberFormat = NumberFormat('#,###');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Genshin Builder'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => context.push('/settings'),
            tooltip: 'データ同期',
          ),
          const ShellMenuButton(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '非公式ファンツール',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  lastSyncAsync.when(
                    data: (dt) => Text(
                      dt == null
                          ? 'マスターデータ未同期 — 設定から同期してください'
                          : '最終同期: ${DateFormat.yMd().add_Hm().format(dt)}',
                    ),
                    loading: () => const Text('読み込み中…'),
                    error: (e, _) => Text(userFacingError(e)),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () =>
                        AppShellScope.of(context).switchMainTab(MainTab.characters.index),
                    icon: const Icon(Icons.people),
                    label: const Text('キャラ一覧'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () =>
                        AppShellScope.of(context).switchMainTab(MainTab.daily.index),
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('今日の曜日素材'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/gacha'),
                    icon: const Icon(Icons.casino_outlined),
                    label: const Text('ガチャ（PUバナー）'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _GrowthCards(),
          const SizedBox(height: 16),
          const DailyNoteCard(),
          const SizedBox(height: 16),
          const HomeEventsCard(),
          const SizedBox(height: 16),
          DeferredLoader(
            builder: (_) => const AdventureStatusCard(),
          ),
          const SizedBox(height: 16),
          DeferredLoader(
            builder: (_) => _BookmarkSection(numberFormat: numberFormat),
          ),
        ],
      ),
    );
  }
}

class _BookmarkSection extends ConsumerWidget {
  const _BookmarkSection({required this.numberFormat});

  final NumberFormat numberFormat;

  Future<void> _removeBookmark(
    BuildContext context,
    WidgetRef ref,
    String materialId,
  ) async {
    final repo = await ref.read(bookmarkRepositoryProvider.future);
    await repo.removeByMaterialId(materialId);
    ref.invalidate(aggregatedBookmarksProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ブックマークから削除しました')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(aggregatedBookmarksProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Text(
            'ブックマーク素材',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          bookmarksAsync.when(
            data: (bookmarks) {
              if (bookmarks.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('ブックマークされた素材はありません'),
                  ),
                );
              }
              return Column(
                children: bookmarks.take(8).map((b) {
                  return Card(
                    child: ListTile(
                      leading: _MaterialIcon(
                        iconUrl: b.iconUrl,
                        isMora: b.isMora,
                      ),
                      title: Text(b.name),
                      subtitle: Text(b.sourceLabels.join(' · ')),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...b.characters.take(3).map(
                                (c) => Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: CircleAvatar(
                                    radius: 14,
                                    backgroundImage: c.characterIconUrl != null
                                        ? CachedNetworkImageProvider(
                                            c.characterIconUrl!,
                                          )
                                        : null,
                                    child: c.characterIconUrl == null
                                        ? Text(
                                            c.characterName.characters.first,
                                            style: const TextStyle(fontSize: 12),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                          const SizedBox(width: 8),
                          Text(numberFormat.format(b.count)),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: '削除',
                            onPressed: () =>
                                _removeBookmark(context, ref, b.materialId),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(userFacingError(e)),
          ),
          if (bookmarksAsync.valueOrNull?.isNotEmpty == true)
            TextButton(
              onPressed: () =>
                  AppShellScope.of(context).switchMainTab(MainTab.materials.index),
              child: const Text('すべて見る'),
            ),
      ],
    );
  }
}

class _MaterialIcon extends StatelessWidget {
  const _MaterialIcon({this.iconUrl, required this.isMora});

  final String? iconUrl;
  final bool isMora;

  @override
  Widget build(BuildContext context) {
    if (isMora) {
      return const CircleAvatar(child: Text('M'));
    }
    if (iconUrl != null && iconUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: iconUrl!,
        width: 40,
        height: 40,
        errorWidget: (_, __, ___) => const Icon(Icons.inventory_2),
      );
    }
    return const Icon(Icons.inventory_2);
  }
}

class _GrowthCards extends ConsumerWidget {
  const _GrowthCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagsAsync = ref.watch(featureFlagsProvider);
    return flagsAsync.when(
      data: (flags) => Column(
        children: [
          if (flags.enableDailyPlan) const _DailyPlanHomeCard(),
          if (flags.enableDailyPlan) const SizedBox(height: 16),
          if (flags.enableAccountHealth) const _HealthHomeCard(),
          if (flags.enableAccountHealth) const SizedBox(height: 16),
          if (flags.enableGrowthTimeline)
            Card(
              child: ListTile(
                leading: const Icon(Icons.timeline),
                title: const Text('\u6210\u9577\u5c65\u6b74'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/growth-timeline'),
              ),
            ),
          if (flags.enableGrowthTimeline) const SizedBox(height: 16),
        ],
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _DailyPlanHomeCard extends ConsumerWidget {
  const _DailyPlanHomeCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(dailyPlanProvider);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('\u4eca\u65e5\u3084\u308b\u3053\u3068', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            planAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Text('\u8aad\u307f\u8fbc\u307f\u30a8\u30e9\u30fc'),
              data: (plan) {
                if (plan.topItems.isEmpty) {
                  return Text('\u80b2\u6210\u76ee\u6a19\u3092\u8a2d\u5b9a\u3059\u308b\u3068\u3001\u4eca\u65e5\u304a\u3059\u3059\u3081\u306e\u80b2\u6210\u9805\u76ee\u304c\u8868\u793a\u3055\u308c\u307e\u3059\u3002',
                      style: theme.textTheme.bodySmall);
                }
                return Column(
                  children: [
                    ...plan.topItems.map((item) => ListTile(
                          dense: true,
                          title: Text(item.title, style: theme.textTheme.bodyMedium),
                          subtitle: item.reasons.isNotEmpty
                              ? Text(item.reasons.first, maxLines: 1, overflow: TextOverflow.ellipsis)
                              : null,
                        )),
                    TextButton(
                      onPressed: () => context.push('/daily-plan'),
                      child: const Text('\u3059\u3079\u3066\u898b\u308b'),
                    ),
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

class _HealthHomeCard extends ConsumerWidget {
  const _HealthHomeCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(accountHealthReportProvider);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('\u30a2\u30ab\u30a6\u30f3\u30c8\u5065\u5eb7\u8a3a\u65ad', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            reportAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Text('\u8aad\u307f\u8fbc\u307f\u30a8\u30e9\u30fc'),
              data: (report) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (report.isEvaluable)
                    Row(
                      children: [
                        Text('${report.totalScore!.toStringAsFixed(0)}\u70b9', style: theme.textTheme.headlineSmall),
                        const SizedBox(width: 8),
                        Text('\u8a55\u4fa1\u53ef\u80fd: ${report.evaluatedCategoryCount}\u30ab\u30c6\u30b4\u30ea'),
                      ],
                    )
                  else
                    Text('\u73fe\u5728\u306e\u30c7\u30fc\u30bf\u3067\u306f\u80b2\u6210\u72b6\u6cc1\u3092\u8a55\u4fa1\u3067\u304d\u307e\u305b\u3093\u3002',
                        style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  if (report.strengths.isNotEmpty)
                    Text('\u5f37\u307f: ${report.strengths.first}', style: theme.textTheme.labelMedium),
                  if (report.improvementCandidates.isNotEmpty)
                    Text('\u6539\u5584\u5019\u88dc: ${report.improvementCandidates.first}', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text('\u30c7\u30fc\u30bf\u30ab\u30d0\u30ec\u30c3\u30b8: ${report.dataCoverage}', style: theme.textTheme.labelSmall),
                  Text('\u672c\u8a3a\u65ad\u306f\u30a2\u30d7\u30ea\u72ec\u81ea\u306e\u80b2\u6210\u6307\u6a19\u3067\u3059', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  TextButton(
                    onPressed: () => context.push('/account-health'),
                    child: const Text('\u8a73\u7d30\u3092\u898b\u308b'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
