import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/planning/build_growth_route_request.dart';
import '../../../providers/growth_providers.dart';
import '../../../domain/recommendation/recommendation.dart';

/// Daily plan detail screen — shows all recommended tasks.
class DailyPlanScreen extends ConsumerWidget {
  const DailyPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(dailyPlanProvider);
    final theme = Theme.of(context);
    // Normalize to date boundary once (not per-item).
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Scaffold(
      appBar: AppBar(title: const Text('\u4eca\u65e5\u3084\u308b\u3053\u3068')),
      body: planAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('\u8aad\u307f\u8fbc\u307f\u30a8\u30e9\u30fc')),
        data: (plan) {
          if (plan.items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('\u80b2\u6210\u76ee\u6a19\u3092\u8a2d\u5b9a\u3059\u308b\u3068\u3001\u4eca\u65e5\u304a\u3059\u3059\u3081\u306e\u80b2\u6210\u9805\u76ee\u304c\u8868\u793a\u3055\u308c\u307e\u3059\u3002',
                    textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
              ),
            );
          }

          // Build GrowthRouteRequest once, not per item.
          final routeReq = buildGrowthRouteRequest(plan, today);

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: plan.items.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == plan.items.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/growth-route', extra: routeReq),
                          icon: const Icon(Icons.route),
                          label: const Text('\u80b2\u6210\u30eb\u30fc\u30c8\u3092\u4f5c\u6210'),
                        ),
                      );
                    }
                    return Card(
                      child: ListTile(
                        title: Text(plan.items[i].title),
                        subtitle: Text('\u512a\u5148\u5ea6: ${plan.items[i].priority}'),
                        trailing: plan.items[i].confidence == RecommendationConfidence.high
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : const Icon(Icons.info_outline),
                      ),
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
