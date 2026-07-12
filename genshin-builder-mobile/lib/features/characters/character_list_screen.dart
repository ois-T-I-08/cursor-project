import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/user_facing_error.dart';
import '../../domain/character_list_sort.dart';
import '../../domain/game_display.dart';
import '../../providers/hoyolab_game_providers.dart';
import '../../providers/hoyolab_game_refresh.dart';
import '../shared/game_icon_image.dart';
import '../shared/shell_menu_button.dart';
import '../artifacts/artifact_sets_screen.dart';

/// キャラ一覧（聖遺物一覧と同じ: 地域セクション + グリッド）。
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
          const ShellMenuButton(),
        ],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(userFacingError(e))),
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

          final fetchMessage = ownedFetchAsync.maybeWhen(
            data: (result) => result.userMessage,
            orElse: () => null,
          );
          // ソート設定に依存せず、常に聖遺物と同じ地域グリッド
          final sections = groupCharacterEntriesByRegion(entries);

          return LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  artifactSetGridCrossAxisCount(constraints.maxWidth);
              return CustomScrollView(
                slivers: [
                  if (fetchMessage != null)
                    SliverToBoxAdapter(
                      child: _OwnedFetchBanner(message: fetchMessage),
                    ),
                  for (final section in sections) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          section.region,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.78,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _CharacterGridTile(
                            entry: section.items[index],
                          ),
                          childCount: section.items.length,
                        ),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _CharacterGridTile extends StatelessWidget {
  const _CharacterGridTile({required this.entry});

  final CharacterListEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = entry.character;
    final elementLabel = elementLabelMap[c.element] ?? c.element;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/characters/${c.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size =
                          constraints.biggest.shortestSide.clamp(36.0, 72.0);
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GameIconImage(
                            iconUrl: c.iconUrl,
                            size: size,
                            borderRadius: 10,
                            fallback: Text(
                              c.name.isNotEmpty ? c.name[0] : '?',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (entry.isOwned)
                            Positioned(
                              right: -4,
                              top: -4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.colorScheme.surface,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  Icons.check,
                                  size: size * 0.28,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                c.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium,
              ),
              Text(
                '$elementLabel · ${c.rarity}★',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
