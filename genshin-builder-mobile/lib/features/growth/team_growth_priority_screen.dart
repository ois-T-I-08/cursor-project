import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/growth_providers.dart';

/// Displays team growth priority.
/// Receives teamId via GoRouterState.extra as String.
/// Falls back to empty if extra is missing or invalid.
class TeamGrowthPriorityScreen extends ConsumerWidget {
  const TeamGrowthPriorityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = GoRouterState.of(context);
    final teamId = state.extra is String ? (state.extra as String) : '';
    final reportAsync = teamId.isNotEmpty ? ref.watch(teamGrowthPriorityProvider(teamId)) : null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('\u7de8\u6210\u80b2\u6210\u512a\u5148\u5ea6')),
      body: reportAsync == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('\u7de8\u6210\u304c\u9078\u629e\u3055\u308c\u3066\u3044\u307e\u305b\u3093',
                    style: theme.textTheme.bodyLarge),
              ),
            )
          : reportAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(child: Text('\u8aad\u307f\u8fbc\u307f\u30a8\u30e9\u30fc', style: theme.textTheme.bodyMedium)),
              data: (report) => _buildReport(context, report),
            ),
    );
  }

  Widget _buildReport(BuildContext context, dynamic report) {
    final theme = Theme.of(context);
    if (report.memberPriorities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('\u7de8\u6210\u30e1\u30f3\u30d0\u30fc\u304c\u3044\u307e\u305b\u3093',
              style: theme.textTheme.bodyLarge),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (report.teamName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(report.teamName, style: theme.textTheme.titleLarge),
          ),
        if (report.sharedMaterialOpportunities.isNotEmpty) ...[
          Semantics(
            label: '\u5171\u6709\u7d20\u6750',
            child: Card(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('\u5171\u6709\u7d20\u6750', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    ...report.sharedMaterialOpportunities.take(3).map(
                          (m) => Text(m, style: theme.textTheme.bodySmall),
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        ...report.memberPriorities.asMap().entries.map((e) {
          final rank = e.key + 1;
          final p = e.value;
          final isUnowned = p.priority < 0;
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: CircleAvatar(child: Text('$rank')),
              title: Text(p.characterId, style: theme.textTheme.bodyMedium),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isUnowned)
                    Text('\u672a\u6240\u6301', style: theme.textTheme.labelSmall?.copyWith(color: Colors.orange))
                  else ...[
                    Text('\u30b9\u30b3\u30a2: ${p.score.toStringAsFixed(2)} | \u512a\u5148\u5ea6: ${p.priority}'),
                    if (p.reasons.isNotEmpty)
                      Text(p.reasons.first, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall),
                  ],
                ],
              ),
              trailing: isUnowned
                  ? Semantics(label: '\u672a\u6240\u6301', child: const Icon(Icons.block, size: 20))
                  : null,
            ),
          );
        }),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '\u30eb\u30fc\u30eb\u30d0\u30fc\u30b8\u30e7\u30f3: ${report.ruleVersion}\n\u672c\u8a3a\u65ad\u306f\u30a2\u30d7\u30ea\u72ec\u81ea\u306e\u80b2\u6210\u6307\u6a19\u3067\u3059',
              style: theme.textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
