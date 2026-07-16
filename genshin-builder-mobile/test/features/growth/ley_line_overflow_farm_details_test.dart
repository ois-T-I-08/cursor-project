import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/planning/ley_line_overflow.dart';
import 'package:genshin_builder_mobile/features/growth/widgets/ley_line_overflow_farm_details.dart';

LeyLineOverflowBreakdown _breakdown({
  bool maxEstimate = true,
  int remaining = 3,
}) {
  return LeyLineOverflowBreakdown(
    normalEquivalentRuns: 9,
    bonusRunsApplied: 3,
    normalRunsAfterBonus: 3,
    actualRuns: 6,
    resinTotal: 120,
    dailyBonusLimit: 3,
    remainingBonusCapacity: remaining,
    isMaxEstimate: maxEstimate,
    eventDisplayName: '地脈の奔流',
    rewardMultiplier: 2,
    bonusUsedToday: maxEstimate ? null : 0,
  );
}

Widget _wrap(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: brightness,
      ),
      useMaterial3: true,
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  test('開催中ラベルは文字で表現', () {
    expect(leyLineOverflowActiveLabel('地脈の奔流'), '地脈の奔流 開催中');
  });

  testWidgets('開催中ラベル表示（ライト）', (tester) async {
    await tester.pumpWidget(
      _wrap(LeyLineOverflowFarmDetails(overflow: _breakdown())),
    );
    expect(find.text('地脈の奔流 開催中'), findsOneWidget);
    expect(find.textContaining('実際の周回数：約6回'), findsOneWidget);
    expect(find.textContaining('ボーナス適用回数：最大3回'), findsOneWidget);
  });

  testWidgets('開催中ラベル表示（ダーク）', (tester) async {
    await tester.pumpWidget(
      _wrap(
        LeyLineOverflowFarmDetails(overflow: _breakdown()),
        brightness: Brightness.dark,
      ),
    );
    expect(find.text('地脈の奔流 開催中'), findsOneWidget);
    final text = tester.widget<Text>(find.text('地脈の奔流 開催中'));
    expect(text.data, '地脈の奔流 開催中');
  });

  testWidgets('使用済み不明の注意表示', (tester) async {
    await tester.pumpWidget(
      _wrap(LeyLineOverflowFarmDetails(overflow: _breakdown())),
    );
    expect(
      find.textContaining('使用済み回数を取得できない'),
      findsOneWidget,
    );
  });

  testWidgets('残り既知時は本日のボーナス残りを表示', (tester) async {
    await tester.pumpWidget(
      _wrap(
        LeyLineOverflowFarmDetails(
          overflow: _breakdown(maxEstimate: false, remaining: 2),
        ),
      ),
    );
    expect(find.textContaining('本日のボーナス残り：2回'), findsOneWidget);
    expect(find.textContaining('使用済み回数を取得できない'), findsNothing);
  });

  testWidgets('周回数にイベント用スタイル（tertiary）', (tester) async {
    await tester.pumpWidget(
      _wrap(LeyLineOverflowFarmDetails(overflow: _breakdown())),
    );
    final runs = tester.widget<Text>(find.text('実際の周回数：約6回'));
    final scheme = Theme.of(
      tester.element(find.text('実際の周回数：約6回')),
    ).colorScheme;
    expect(runs.style?.color, scheme.tertiary);
  });
}
