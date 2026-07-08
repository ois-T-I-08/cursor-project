import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';

class CharacterListScreen extends ConsumerWidget {
  const CharacterListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charactersAsync = ref.watch(charactersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('キャラクター')),
      body: charactersAsync.when(
        data: (characters) {
          if (characters.isEmpty) {
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
          return ListView.builder(
            itemCount: characters.length,
            itemBuilder: (context, index) {
              final c = characters[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: CachedNetworkImageProvider(c.iconUrl),
                ),
                title: Text(c.name),
                subtitle: Text('${c.region} · ${c.rarity}★'),
                trailing: Text(c.element),
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
}
