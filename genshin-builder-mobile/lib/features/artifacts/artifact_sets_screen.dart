import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/user_facing_error.dart';
import '../../domain/artifacts/artifact_set_overview.dart';
import '../../providers/artifact_sets_page_providers.dart';
import '../../providers/character_detail_providers.dart';
import '../../providers/hoyolab_game_providers.dart';
import '../shared/game_icon_image.dart';
import 'widgets/artifact_set_detail_dialog.dart';

/// 画面幅に応じたグリッド列数（横スクロールなし）。
int artifactSetGridCrossAxisCount(double width) {
  if (width < 360) return 3;
  if (width < 600) return 4;
  if (width < 900) return 5;
  return 6;
}

class ArtifactSetsScreen extends ConsumerWidget {
  const ArtifactSetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(artifactSetOverviewsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('聖遺物'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読み込み',
            onPressed: () {
              ref.read(amberDetailRepositoryProvider).clearArtifactSetsCache();
              ref.read(hoyolabGameDataCacheProvider).clear();
              ref.invalidate(hoyolabOwnedFetchResultProvider);
              ref.invalidate(artifactSetsProvider);
              ref.invalidate(artifactSetOverviewsProvider);
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(userFacingError(e)),
              ),
            ),
        data: (overviews) {
          if (overviews.isEmpty) {
            return const Center(child: Text('聖遺物セットがありません'));
          }
          final sections = groupArtifactSetOverviewsByRegion(overviews);
          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = artifactSetGridCrossAxisCount(
                constraints.maxWidth,
              );
              return CustomScrollView(
                slivers: [
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
                          (context, index) => _ArtifactSetGridTile(
                            overview: section.items[index],
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

class _ArtifactSetGridTile extends StatelessWidget {
  const _ArtifactSetGridTile({required this.overview});

  final ArtifactSetOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final set = overview.set;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap:
            () => showArtifactSetDetailDialog(
              context: context,
              overview: overview,
            ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest.shortestSide.clamp(
                        36.0,
                        72.0,
                      );
                      return GameIconImage(
                        iconUrl: set.iconUrl,
                        size: size,
                        borderRadius: 10,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                set.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
