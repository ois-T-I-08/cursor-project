import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_builder_mobile/data/team_recommendations/backend_team_recommendation_api.dart';
import 'package:genshin_builder_mobile/domain/team_recommendation/team_recommendation.dart';

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

  test('GET parses completed observed recommendation', () async {
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
                'engine': 'aza+rules',
                'warning': 'abyssUnavailable',
                'recommendations': [
                  {
                    'members': ['10000089', '10000087', '10000025', '10000054'],
                    'score': 0.92,
                    'simulationStatus': 'observed',
                    'sourceTypes': ['aza'],
                    'rotationConfidence': 'medium',
                    'observedByAza': true,
                    'inputQuality': 'partial',
                    'reasons': ['AZA.GGの深境螺旋で使用実績があります'],
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
    expect(job.result?.engine, 'aza+rules');
    expect(job.result?.warning, 'abyssUnavailable');
    expect(job.result?.recommendations.single.observedByAza, isTrue);
    expect(job.result?.recommendations.single.alternatives['10000054'], [
      '10000032',
    ]);
  });
}
