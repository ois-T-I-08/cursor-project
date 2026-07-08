import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/app_providers.dart';

class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  Future<void> _removeMaterial(
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

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ブックマークをすべて削除'),
        content: const Text('登録済みの素材ブックマークをすべて削除します。よろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final repo = await ref.read(bookmarkRepositoryProvider.future);
    await repo.clearAll();
    ref.invalidate(aggregatedBookmarksProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('すべてのブックマークを削除しました')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarksAsync = ref.watch(aggregatedBookmarksProvider);
    final fmt = NumberFormat('#,###');

    return Scaffold(
      appBar: AppBar(
        title: const Text('素材ブックマーク'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'すべて削除',
            onPressed: bookmarksAsync.valueOrNull?.isEmpty == true
                ? null
                : () => _clearAll(context, ref),
          ),
        ],
      ),
      body: bookmarksAsync.when(
        data: (bookmarks) {
          if (bookmarks.isEmpty) {
            return const Center(
              child: Text('ブックマークされた素材はありません'),
            );
          }
          return ListView.separated(
            itemCount: bookmarks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final b = bookmarks[index];
              return ListTile(
                leading: b.isMora
                    ? const CircleAvatar(child: Text('M'))
                    : (b.iconUrl != null
                        ? CachedNetworkImage(
                            imageUrl: b.iconUrl!,
                            width: 40,
                            height: 40,
                          )
                        : const Icon(Icons.inventory_2)),
                title: Text(b.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.sourceLabels.join('\n')),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: b.characters
                          .map(
                            (c) => Chip(
                              avatar: c.characterIconUrl != null
                                  ? CircleAvatar(
                                      backgroundImage:
                                          CachedNetworkImageProvider(
                                        c.characterIconUrl!,
                                      ),
                                    )
                                  : null,
                              label: Text(c.characterName),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fmt.format(b.count),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '削除',
                      onPressed: () =>
                          _removeMaterial(context, ref, b.materialId),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
      ),
    );
  }
}
