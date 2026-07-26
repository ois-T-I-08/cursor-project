import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/battle_statistics_providers.dart';
import 'router.dart';

class GenshinBuilderApp extends ConsumerStatefulWidget {
  const GenshinBuilderApp({super.key});

  @override
  ConsumerState<GenshinBuilderApp> createState() => _GenshinBuilderAppState();
}

class _GenshinBuilderAppState extends ConsumerState<GenshinBuilderApp> {
  @override
  void initState() {
    super.initState();
    if (ref.read(battleStatisticsSyncEnabledProvider)) {
      unawaited(_startBattleStatisticsSync());
    }
  }

  Future<void> _startBattleStatisticsSync() async {
    try {
      await ref.read(battleStatisticsStartupSyncProvider.future);
    } catch (_) {
      // 起動と既存ローカルデータの利用を妨げない。
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Genshin Builder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A6FA5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: appRouter,
    );
  }
}
