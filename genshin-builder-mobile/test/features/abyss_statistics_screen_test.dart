import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:genshin_builder_mobile/domain/abyss/abyss_statistics.dart';
import 'package:genshin_builder_mobile/features/abyss/abyss_statistics_screen.dart';
import 'package:genshin_builder_mobile/providers/abyss_statistics_providers.dart';

import '../support/abyss_statistics_fixture.dart';

void main() {
  testWidgets('shows a dedicated loading state', (tester) async {
    final pending = Completer<AbyssStatistics>();
    await tester.pumpWidget(_app((ref) => pending.future));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('統計データを読み込んでいます…'), findsOneWidget);
  });

  testWidgets('shows safe error text and a retry action', (tester) async {
    await tester.pumpWidget(
      _app(
        (ref) async =>
            throw const AbyssStatisticsException(
              AbyssStatisticsFailure.rateLimited,
            ),
      ),
    );
    await _settleProvider(tester);

    expect(find.textContaining('混み合っています'), findsOneWidget);
    expect(find.text('再試行'), findsOneWidget);
    expect(find.textContaining('stack'), findsNothing);
  });

  testWidgets('retry invalidates the provider and renders recovered data', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      _app((ref) async {
        attempts++;
        if (attempts == 1) {
          throw const AbyssStatisticsException(
            AbyssStatisticsFailure.networkError,
          );
        }
        return sampleAbyssStatistics();
      }),
    );
    await _settleProvider(tester);

    expect(find.text('再試行'), findsOneWidget);
    await tester.tap(find.text('再試行'));
    await _settleProvider(tester);

    expect(attempts, 2);
    expect(find.text('AZA.GG 深境螺旋統計'), findsOneWidget);
  });

  testWidgets('shows update, sample, disclaimer and AZA.GG credit', (
    tester,
  ) async {
    final statistics = sampleAbyssStatistics();
    await tester.pumpWidget(_app((ref) async => statistics));
    await _settleProvider(tester);

    expect(find.text('AZA.GG 深境螺旋統計'), findsOneWidget);
    expect(find.text('42（ref 84）'), findsOneWidget);
    expect(find.text('最終取得'), findsOneWidget);
    expect(
      find.text(
        DateFormat(
          'yyyy/MM/dd HH:mm',
        ).format(statistics.metadata.fetchedAt.toLocal()),
      ),
      findsOneWidget,
    );
    expect(find.text('投稿データに基づく参考統計です。'), findsOneWidget);
    expect(find.text('Statistics data provided by AZA.GG'), findsOneWidget);
    expect(find.textContaining('ゲームバージョンではありません'), findsOneWidget);
    expect(find.text('今期の使用率 87.6%'), findsOneWidget);
    expect(find.textContaining('use_rate'), findsNothing);
    expect(find.textContaining('phase'), findsNothing);
    expect(find.textContaining('sample_size_x_a'), findsNothing);
  });

  testWidgets('shows an explicit stale cache warning', (tester) async {
    await tester.pumpWidget(
      _app((ref) async => sampleAbyssStatistics(isStale: true)),
    );
    await _settleProvider(tester);

    expect(find.text('前回取得した統計データを表示しています。最新情報ではない可能性があります。'), findsOneWidget);
  });

  testWidgets('shows a successful empty state', (tester) async {
    await tester.pumpWidget(
      _app(
        (ref) async =>
            sampleAbyssStatistics(characters: const [], teams: const []),
      ),
    );
    await _settleProvider(tester);

    expect(find.text('表示できるキャラクター統計がありません。'), findsOneWidget);
  });
}

Widget _app(Future<AbyssStatistics> Function(Ref ref) create) {
  return ProviderScope(
    overrides: [abyssStatisticsProvider.overrideWith(create)],
    child: const MaterialApp(home: AbyssStatisticsScreen()),
  );
}

Future<void> _settleProvider(WidgetTester tester) {
  return tester.pumpAndSettle(
    const Duration(milliseconds: 10),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
}
