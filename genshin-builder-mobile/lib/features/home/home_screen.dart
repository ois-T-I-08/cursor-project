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
            onPressed: () => context.go('/settings'),
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
                    onPressed: () => context.go('/characters'),
                    icon: const Icon(Icons.people),
                    label: const Text('キャラ一覧'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/daily'),
                    icon: const Icon(Icons.calendar_today),
                    label: const Text('今日の曜日素材'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/gacha'),
                    icon: const Icon(Icons.casino_outlined),
                    label: const Text('ガチャ（PUバナー）'),
                  ),
                ],
              ),
            ),
          ),
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
              onPressed: () => context.go('/bookmarks'),
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
