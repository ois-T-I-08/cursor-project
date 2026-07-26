import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_builder_mobile/data/team_recommendations/backend_team_recommendation_api.dart';
import 'package:genshin_builder_mobile/domain/team_recommendation/team_recommendation.dart';
import 'package:genshin_builder_mobile/domain/team_recommendation/team_template_replacement.dart';

void main() {
  const id = '123e4567-e89b-42d3-a456-426614174000';
  test('POST sends normalized DTO without Cookie or UID', () async {
    late String body;
    final api = BackendTeamRecommendationApi(
      baseUrl: 'https://builder.example.com',
      client: MockClient((request) async {
        body = request.body;
        expect(request.url.path, '/api/team-recommendations');
        expect(request.method, 'POST');
        return http.Response(
          jsonEncode({'jobId': id, 'status': 'queued'}),
          202,
        );
      }),
    );
    final job = await api.enqueue(
      const TeamRecommendationRequest(
        attackerId: '10000089',
        half: 'upper',
        ownedOnly: true,
        enemy: 'single',
        preference: 'damage',
        characters: [
          SimulationBuildSnapshot(
            characterId: '10000089',
            element: 'hydro',
            rarity: 5,
            isOwned: true,
            level: 90,
            ascension: 6,
            constellation: 0,
            inputQuality: SimulationInputQuality.partial,
          ),
        ],
      ),
    );
    expect(job.status, TeamSimulationJobStatus.queued);
    expect(body.toLowerCase(), isNot(contains('cookie')));
    expect(body.toLowerCase(), isNot(contains('uid')));
  });

  test('GET parses completed stale recommendation', () async {
    final api = BackendTeamRecommendationApi(
      baseUrl: 'https://builder.example.com',
      client: MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'jobId': id,
              'status': 'completed',
              'result': {
                'attackerId': '10000089',
                'generatedAt': '2026-07-20T00:00:00Z',
                'gcsim': {
                  'version': 'v2.43.4',
                  'iterations': 1000,
                  'enabled': true,
                },
                'warning': 'staleSimulation',
                'recommendations': [
                  {
                    'members': ['10000089', '10000087', '10000025', '10000054'],
                    'score': 0.92,
                    'estimatedDps': 78543.2,
                    'simulationStatus': 'simulated',
                    'sourceTypes': ['aza', 'gcsim'],
                    'rotationConfidence': 'medium',
                    'observedByAza': true,
                    'isCached': true,
                    'isStale': true,
                    'inputQuality': 'partial',
                    'reasons': ['前回の正常値'],
                    'alternatives': {
                      '10000054': ['10000032'],
                    },
                  },
                ],
              },
            }),
          ),
          200,
        );
      }),
    );
    final job = await api.getJob(id);
    expect(job.result?.warning, 'staleSimulation');
    expect(job.result?.recommendations.single.isStale, isTrue);
    expect(job.result?.recommendations.single.alternatives['10000054'], [
      '10000032',
    ]);
  });

  test('GET parses approved templates without exposing admin data', () async {
    final api = BackendTeamRecommendationApi(
      baseUrl: 'https://builder.example.com',
      client: MockClient((request) async {
        expect(request.url.path, '/api/team-templates');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'templates': [
                {
                  'id': 'template-12345',
                  'name': '承認済み編成',
                  'archetype': 'reaction',
                  'members': [
                    {
                      'characterId': '10000058',
                      'role': 'healer',
                      'slotIndex': 3,
                    },
                    {
                      'characterId': '10000089',
                      'role': 'main_dps',
                      'slotIndex': 0,
                    },
                    {
                      'characterId': '10000071',
                      'role': 'support',
                      'slotIndex': 2,
                    },
                    {
                      'characterId': '10000052',
                      'role': 'sub_dps',
                      'slotIndex': 1,
                    },
                  ],
                  'source': 'local',
                  'sourceUrl': null,
                  'dataVersion': 'v1',
                  'updatedAt': '2026-07-26T00:00:00.000Z',
                },
              ],
            }),
          ),
          200,
        );
      }),
    );
    final templates = await api.getTemplates();
    expect(templates.single.name, '承認済み編成');
    expect(templates.single.members, hasLength(4));
    expect(templates.single.members.map((member) => member.slotIndex), [
      0,
      1,
      2,
      3,
    ]);
    expect(templates.single.members.last.role, 'healer');
  });

  test('GET parses pre-generated replacement candidates', () async {
    final api = BackendTeamRecommendationApi(
      baseUrl: 'https://builder.example.com',
      client: MockClient((request) async {
        expect(
          request.url.path,
          '/api/team-templates/template-12345/replacements/10000052',
        );
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'templateId': 'template-12345',
              'replacedCharacterId': '10000052',
              'generatedAt': '2026-07-26T00:00:00.000Z',
              'dataVersion': 'v1',
              'isStale': false,
              'source': 'deepseek',
              'slotAnalysis': {
                'requiredFunctions': ['hydro_applier'],
                'preferredFunctions': [],
                'dependencies': [],
                'replacementRisks': [],
              },
              'candidates': [
                {
                  'characterId': '10000031',
                  'element': 'hydro',
                  'roles': ['sub_dps'],
                  'tags': ['off_field_dps'],
                  'compatibilityScore': 88,
                  'category': 'optimal',
                  'confidence': 0.9,
                  'reasons': ['役割を維持'],
                  'tradeoffs': [],
                  'requiredChanges': [],
                  'teamEvaluation': {
                    'reactionViability': 90,
                    'damageBalance': 85,
                    'sustain': 70,
                    'energy': 80,
                    'fieldTimeBalance': 90,
                  },
                  'deterministicPenalty': 0,
                  'finalScore': 88,
                },
              ],
            }),
          ),
          200,
        );
      }),
    );
    final result = await api.getReplacement(
      templateId: 'template-12345',
      characterId: '10000052',
    );
    expect(result.candidates.single.category, ReplacementCategory.optimal);
    expect(result.candidates.single.finalScore, 88);
  });
}
