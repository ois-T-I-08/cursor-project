import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class GenshinBuilderApp extends ConsumerWidget {
  const GenshinBuilderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
