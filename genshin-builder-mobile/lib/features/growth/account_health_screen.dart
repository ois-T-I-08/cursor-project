import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/growth_providers.dart';

/// Account health report screen.
class AccountHealthScreen extends ConsumerWidget {
  const AccountHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(accountHealthReportProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('\u30a2\u30ab\u30a6\u30f3\u30c8\u5065\u5eb7\u8a3a\u65ad')),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const Center(child: Text('\u8aad\u307f\u8fbc\u307f\u30a8\u30e9\u30fc')),
        data: (report) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Total score
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text('\u7dcf\u5408\u8a55\u4fa1', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (report.isEvaluable)
                        Text('${report.totalScore!.toStringAsFixed(0)}\u70b9', style: theme.textTheme.headlineLarge)
                      else
                        Text('\u8a55\u4fa1\u3067\u304d\u308b\u30c7\u30fc\u30bf\u304c\u3042\u308a\u307e\u305b\u3093', style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 4),
                      Text('\u30c7\u30fc\u30bf\u30ab\u30d0\u30ec\u30c3\u30b8: ${report.dataCoverage}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Categories
              ...report.categories.map((cat) => Card(
                    child: ListTile(
                      title: Text(cat.name),
                      subtitle: Text(cat.evaluated
                          ? '${cat.normalizedScore.toStringAsFixed(0)}% | ${cat.reasons.join(", ")}'
                          : '\u8a55\u4fa1\u4e0d\u80fd'),
                      trailing: cat.evaluated ? null : const Icon(Icons.help_outline),
                    ),
                  )),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('\u672c\u8a3a\u65ad\u306f\u30a2\u30d7\u30ea\u72ec\u81ea\u306e\u80b2\u6210\u6307\u6a19\u3067\u3059',
                      style: theme.textTheme.labelSmall,
                      textAlign: TextAlign.center),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
