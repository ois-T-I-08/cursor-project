import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/hoyolab_home_providers.dart';
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
    Future.microtask(() => prefetchHoyolabHomeData(ref));
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
