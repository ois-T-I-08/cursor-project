import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/hoyolab/models/game_record.dart';
import '../../domain/character_list_sort.dart';
import '../../providers/hoyolab_game_providers.dart';
import '../../../providers/hoyolab_game_refresh.dart';

class CharacterListScreen extends ConsumerWidget {
  const CharacterListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(sortedCharacterEntriesProvider);
    final ownedFetchAsync = ref.watch(hoyolabOwnedFetchResultProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('キャラクター'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '所持情報を更新',
            onPressed: () => refreshHoyolabOwnedCharacters(ref),
          ),
        ],
      ),
      body: entriesAsync.when(
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('キャラデータがありません'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.go('/settings'),
                    child: const Text('設定で同期する'),
                  ),
                ],
              ),
            );
          }

          final ownedCount =
              entries.where((entry) => entry.isOwned).length;
          final hasOwned = ownedCount > 0;
          final fetchMessage = ownedFetchAsync.maybeWhen(
            data: (result) => result.userMessage,
            orElse: () => null,
          );

          return ListView.builder(
            itemCount: _itemCount(
              entries,
              hasOwned: hasOwned,
              showBanner: fetchMessage != null,
            ),
            itemBuilder: (context, index) {
              if (fetchMessage != null && index == 0) {
                return _OwnedFetchBanner(message: fetchMessage);
              }
              final listIndex = fetchMessage != null ? index - 1 : index;
              final item = _resolveItem(entries, listIndex, hasOwned: hasOwned);
              if (item is _SectionHeader) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                );
              }

              final entry = item as CharacterListEntry;
              final c = entry.character;
              final ownedLabel = _ownedSubtitle(entry);

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: CachedNetworkImageProvider(c.iconUrl),
                ),
                title: Text(c.name),
                subtitle: Text(
                  ownedLabel ?? '${c.region} · ${c.rarity}★',
                ),
                trailing: entry.isOwned
                    ? Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : Text(c.element),
                onTap: () => context.go('/characters/${c.id}'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
      ),
    );
  }

  String? _ownedSubtitle(CharacterListEntry entry) {
    final owned = entry.owned;
    if (owned == null) return null;
    final obtained = formatRelativeObtained(owned.obtainedAt);
    if (obtained != null) {
      return '${entry.character.rarity}★ · Lv.${owned.level} · $obtained';
    }
    return '${entry.character.rarity}★ · Lv.${owned.level} · 所持';
  }

  int _itemCount(
    List<CharacterListEntry> entries, {
    required bool hasOwned,
    bool showBanner = false,
  }) {
    var count = entries.length;
    if (showBanner) count += 1;
    if (hasOwned) count += 1;
    if (entries.length > ownedCount(entries)) count += 1;
    return count;
  }

  int ownedCount(List<CharacterListEntry> entries) =>
      entries.where((e) => e.isOwned).length;

  Object _resolveItem(
    List<CharacterListEntry> entries,
    int index, {
    required bool hasOwned,
  }) {
    var cursor = 0;
    if (hasOwned) {
      if (index == cursor) {
        return const _SectionHeader('所持キャラクター');
      }
      cursor++;
    }

    final ownedLen = ownedCount(entries);
    final ownedEntries = entries.take(ownedLen);
    final unownedEntries = entries.skip(ownedLen);

    if (index < cursor + ownedLen) {
      return ownedEntries.elementAt(index - cursor);
    }
    cursor += ownedLen;

    if (unownedEntries.isNotEmpty) {
      if (index == cursor) {
        return const _SectionHeader('未所持キャラクター');
      }
      cursor++;
      return unownedEntries.elementAt(index - cursor);
    }

    return entries.last;
  }
}

class _SectionHeader {
  const _SectionHeader(this.title);

  final String title;
}

class _OwnedFetchBanner extends StatelessWidget {
  const _OwnedFetchBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
