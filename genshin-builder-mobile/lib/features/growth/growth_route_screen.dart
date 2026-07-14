import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/planning/growth_route.dart';
import '../../../domain/planning/growth_route_request.dart';
import '../../../providers/growth_providers.dart';

/// Displays a multi-day growth route.
/// Receives [GrowthRouteRequest] via GoRouterState.extra.
/// Falls back to empty route if extra is missing or invalid.
class GrowthRouteScreen extends ConsumerWidget {
  const GrowthRouteScreen({super.key});

  GrowthRouteRequest? _resolveRequest(BuildContext context) {
    final state = GoRouterState.of(context);
    final extra = state.extra;
    if (extra is GrowthRouteRequest) return extra;
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final req = _resolveRequest(context);
    final routeAsync = req != null ? ref.watch(growthRouteProvider(req)) : null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('\u80b2\u6210\u30eb\u30fc\u30c8')),
      body: routeAsync == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('\u80b2\u6210\u76ee\u6a19\u304c\u8a2d\u5b9a\u3055\u308c\u3066\u3044\u307e\u305b\u3093',
                    style: theme.textTheme.bodyLarge),
              ),
            )
          : routeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(child: Text('\u8aad\u307f\u8fbc\u307f\u30a8\u30e9\u30fc', style: theme.textTheme.bodyMedium)),
              data: (route) => _buildRoute(context, route),
            ),
    );
  }

  Widget _buildRoute(BuildContext context, GrowthRoute route) {
    final theme = Theme.of(context);
    if (route.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('\u80b2\u6210\u76ee\u6a19\u304c\u8a2d\u5b9a\u3055\u308c\u3066\u3044\u307e\u305b\u3093',
              style: theme.textTheme.bodyLarge),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${route.startDate.month}/${route.startDate.day} \u301c ${route.endDate.month}/${route.endDate.day}',
                    style: theme.textTheme.titleMedium),
                if (route.unresolvedCosts.isNotEmpty)
                  Text('\u672a\u89e3\u6c7a: ${route.unresolvedCosts.length}\u4ef6',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...route.days.map((day) => _DayCard(day: day)),
        if (route.unresolvedCosts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('\u672a\u89e3\u6c7a\u30b3\u30b9\u30c8', style: theme.textTheme.titleSmall),
          ...route.unresolvedCosts.map((id) => ListTile(dense: true, title: Text(id, style: theme.textTheme.bodySmall))),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text('\u30eb\u30fc\u30eb\u30d0\u30fc\u30b8\u30e7\u30f3: ${route.ruleVersion}',
                style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});
  final GrowthRouteDay day;

  String _weekdayLabel(int w) {
    const labels = ['\u6708', '\u706b', '\u6c34', '\u6728', '\u91d1', '\u571f', '\u65e5'];
    return labels[(w - 1).clamp(0, 6)];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${day.date.month}/${day.date.day} ($_weekdayLabel(day.weekday))',
                style: theme.textTheme.titleSmall),
            if (day.estimatedResinUsed != null)
              Text('\u6a39\u8102: \u2248${day.estimatedResinUsed}', style: theme.textTheme.labelSmall),
            const Divider(),
            if (day.actions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('\u4e88\u5b9a\u306a\u3057', style: theme.textTheme.bodySmall),
              )
            else
              ...day.actions.map((a) => ListTile(
                    dense: true,
                    title: Text(a.optionId, style: theme.textTheme.bodySmall),
                    subtitle: Text('${a.actionType} | P${a.priority}'),
                  )),
          ],
        ),
      ),
    );
  }
}
