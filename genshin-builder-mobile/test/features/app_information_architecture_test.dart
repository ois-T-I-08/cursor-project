import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/features/growth/growth_hub_screen.dart';
import 'package:genshin_builder_mobile/features/more/more_screen.dart';
import 'package:genshin_builder_mobile/providers/gacha_providers.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('GrowthHubScreen', () {
    testWidgets('育成機能を目的別の3セクションに整理する', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GrowthHubScreen()));

      expect(find.text('今日と計画'), findsOneWidget);
      expect(find.text('集めるもの'), findsOneWidget);
      expect(find.text('今日の曜日素材'), findsOneWidget);
      expect(find.text('育成ルート'), findsOneWidget);
      expect(find.text('素材ブックマーク'), findsOneWidget);
      expect(find.text('聖遺物'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('アカウント健康診断'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('振り返る'), findsOneWidget);
      expect(find.text('成長履歴'), findsOneWidget);
      expect(find.text('アカウント健康診断'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('文字サイズ2倍かつ狭い端末でもoverflowしない', (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
          home: const GrowthHubScreen(),
        ),
      );

      expect(find.text('育成を計画する'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('項目タップで対応する詳細ルートを開く', (tester) async {
      final router = GoRouter(
        initialLocation: '/growth',
        routes: [
          GoRoute(path: '/growth', builder: (_, __) => const GrowthHubScreen()),
          GoRoute(
            path: '/bookmarks',
            builder: (_, __) => const Scaffold(body: Text('ブックマーク詳細ルート')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('素材ブックマーク'));
      await tester.pumpAndSettle();

      expect(find.text('ブックマーク詳細ルート'), findsOneWidget);
    });
  });

  group('MoreScreen', () {
    testWidgets('補助機能と管理機能をまとめて表示する', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeCalendarEventsProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(home: MoreScreen()),
        ),
      );

      expect(find.text('ゲーム情報'), findsOneWidget);
      expect(find.text('ガチャ'), findsOneWidget);
      expect(find.text('開催中の情報'), findsOneWidget);
      expect(find.text('アカウント'), findsOneWidget);
      expect(find.text('連携と管理'), findsOneWidget);
      expect(find.text('HoYoLAB連携'), findsOneWidget);
      expect(find.text('設定'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
