import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/errors/user_facing_error.dart';
import '../../domain/gacha/gacha_banner.dart';
import '../../providers/app_providers.dart';
import '../../providers/gacha_providers.dart';
import '../shared/game_icon_image.dart';
import '../shared/shell_menu_button.dart';

class GachaScreen extends ConsumerWidget {
  const GachaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(gachaBannersProvider);
    final charactersAsync = ref.watch(charactersProvider);
    final weaponsAsync = ref.watch(weaponsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ガチャ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
            onPressed: () => ref.invalidate(gachaBannersProvider),
          ),
          const ShellMenuButton(),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(userFacingError(e)),
          ),
        ),
        data: (result) {
          final characters = charactersAsync.valueOrNull ?? const [];
          final weapons = weaponsAsync.valueOrNull ?? const [];
          final byChar = {for (final c in characters) c.id: c};
          final byWeapon = {for (final w in weapons) w.id: w};

          if (result.banners.isEmpty) {
            return const Center(child: Text('バナー情報がありません'));
          }

          return Column(
            children: [
              if (result.hasLiveError)
                ColoredBox(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.wifi_off,
                          size: 18,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '開催中バナーの取得に失敗したため、履歴のみ表示しています',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: result.banners.length,
                  itemBuilder: (context, index) {
                    final banner = result.banners[index];
                    final icons = resolveGachaFeaturedIcons(
                      banner: banner,
                      charactersById: byChar,
                      weaponsById: byWeapon,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _BannerCard(banner: banner, featured: icons),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.banner,
    required this.featured,
  });

  final GachaBanner banner;
  final List<GachaFeaturedIcon> featured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    final status = banner.statusAt(now);
    final dateFormat = DateFormat('yyyy/MM/dd HH:mm');
    final startLocal = banner.start.toLocal();
    final endLocal = banner.end.toLocal();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (status == GachaBannerStatus.active) ...[
                  Chip(
                    label: const Text('開催中'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else if (status == GachaBannerStatus.upcoming) ...[
                  const Chip(
                    label: Text('予告'),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    banner.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  gachaBannerTypeLabel(banner.type),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (banner.version.isNotEmpty)
                  Text(
                    'Ver.${banner.version}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${dateFormat.format(startLocal)} 〜 ${dateFormat.format(endLocal)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (featured.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in featured)
                    _FeaturedIcon(item: f),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeaturedIcon extends StatelessWidget {
  const _FeaturedIcon({required this.item});

  final GachaFeaturedIcon item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GameIconImage(
          iconUrl: item.iconUrl,
          size: 44,
          borderRadius: 8,
          fallback: Text(
            item.label.isNotEmpty ? item.label[0] : '?',
            style: theme.textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 56,
          child: Text(
            item.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ],
    );

    if (item.characterId == null) return child;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push('/characters/${item.characterId}'),
      child: child,
    );
  }
}
