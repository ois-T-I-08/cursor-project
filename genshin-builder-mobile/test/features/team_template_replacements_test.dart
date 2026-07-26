import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/team_recommendation/team_template_replacement.dart';
import 'package:genshin_builder_mobile/features/teams/team_template_replacements.dart';
import 'package:genshin_builder_mobile/providers/app_providers.dart';
import 'package:genshin_builder_mobile/providers/team_recommendation_providers.dart';

void main() {
  testWidgets('承認済みテンプレートの各スロットに入れ替え候補を表示する', (tester) async {
    const characters = [
      MasterCharacter(
        id: '10000089',
        name: 'キャラ1',
        element: 'pyro',
        weaponType: 'sword',
        rarity: 5,
        region: 'test',
        iconUrl: '',
      ),
      MasterCharacter(
        id: '10000052',
        name: 'キャラ2',
        element: 'hydro',
        weaponType: 'sword',
        rarity: 5,
        region: 'test',
        iconUrl: '',
      ),
      MasterCharacter(
        id: '10000071',
        name: 'キャラ3',
        element: 'anemo',
        weaponType: 'sword',
        rarity: 5,
        region: 'test',
        iconUrl: '',
      ),
      MasterCharacter(
        id: '10000058',
        name: 'キャラ4',
        element: 'geo',
        weaponType: 'sword',
        rarity: 5,
        region: 'test',
        iconUrl: '',
      ),
    ];
    final template = PublishedTeamTemplate(
      id: 'template-12345',
      name: '承認済み編成',
      archetype: 'reaction',
      members: const [
        TeamTemplateMember(
          characterId: '10000089',
          role: 'main_dps',
          slotIndex: 0,
        ),
        TeamTemplateMember(
          characterId: '10000052',
          role: 'sub_dps',
          slotIndex: 1,
        ),
        TeamTemplateMember(
          characterId: '10000071',
          role: 'support',
          slotIndex: 2,
        ),
        TeamTemplateMember(
          characterId: '10000058',
          role: 'healer',
          slotIndex: 3,
        ),
      ],
      source: 'local',
      sourceUrl: null,
      dataVersion: 'v1',
      updatedAt: DateTime.utc(2026, 7, 26),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          charactersProvider.overrideWith((ref) async => characters),
          teamTemplatesProvider.overrideWith((ref) async => [template]),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PublishedTeamTemplatesSection(attackerId: '10000089'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('承認済み編成'), findsOneWidget);
    expect(find.text('入れ替え候補'), findsNWidgets(4));
    expect(find.text('出典: 承認済みローカルデータ／更新: 2026-07-26'), findsOneWidget);
  });
}
