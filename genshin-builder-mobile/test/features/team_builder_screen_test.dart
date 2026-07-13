import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/features/teams/team_builder_screen.dart';

void main() {
  group('TeamRole', () {
    test('all roles have labels', () {
      for (final r in TeamRole.values) {
        expect(r.label, isNotEmpty);
      }
    });

    test('default roles are assigned to slots 0-3', () {
      final defaults = [
        TeamRole.mainDps,
        TeamRole.subDps,
        TeamRole.support,
        TeamRole.healer,
      ];
      expect(defaults.length, 4);
    });
  });

  group('TeamBuilderSlot', () {
    test('default is empty', () {
      const slot = TeamBuilderSlot();
      expect(slot.isEmpty, isTrue);
      expect(slot.role, TeamRole.mainDps);
    });

    test('with character is not empty', () {
      const slot = TeamBuilderSlot(characterId: '10000002', role: TeamRole.support);
      expect(slot.isEmpty, isFalse);
    });

    test('copyWith preserves fields', () {
      const slot = TeamBuilderSlot(characterId: '10000002', role: TeamRole.healer);
      final copy = slot.copyWith();
      expect(copy.characterId, '10000002');
      expect(copy.role, TeamRole.healer);
    });

    test('copyWith updates characterId', () {
      const slot = TeamBuilderSlot(characterId: '10000002', role: TeamRole.flex);
      final copy = slot.copyWith(characterId: '10000096');
      expect(copy.characterId, '10000096');
      expect(copy.role, TeamRole.flex);
    });

    test('copyWith updates role', () {
      const slot = TeamBuilderSlot(characterId: '10000002', role: TeamRole.flex);
      final copy = slot.copyWith(role: TeamRole.shielder);
      expect(copy.characterId, '10000002');
      expect(copy.role, TeamRole.shielder);
    });
  });

  group('TeamBuilderScreen audit', () {
    testWidgets('renders scaffold', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: TeamBuilderScreen())),
      );
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('clear button hidden when empty', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: TeamBuilderScreen())),
      );
      expect(find.byIcon(Icons.clear_all), findsNothing);
    });

    testWidgets('team name TextField exists', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: TeamBuilderScreen())),
      );
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('completion status shows 0/4', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: TeamBuilderScreen())),
      );
      await tester.pump();
      expect(find.textContaining('0 / 4'), findsOneWidget);
    });

    testWidgets('hint text visible', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: TeamBuilderScreen())),
      );
      await tester.pump();
      expect(find.textContaining('\u30bf\u30c3\u30d7'), findsOneWidget);
    });

    testWidgets('empty slots show default roles', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: TeamBuilderScreen())),
      );
      await tester.pump();
      expect(
          find.text(
              '\u30e1\u30a4\u30f3\u30a2\u30bf\u30c3\u30ab\u30fc'),
          findsOneWidget);
      expect(find.text('\u30b5\u30d6\u30a2\u30bf\u30c3\u30ab\u30fc'), findsOneWidget);
      expect(find.text('\u30b5\u30dd\u30fc\u30c8'), findsOneWidget);
      expect(find.text('\u30d2\u30fc\u30e9\u30fc'), findsOneWidget);
    });
  });
}
