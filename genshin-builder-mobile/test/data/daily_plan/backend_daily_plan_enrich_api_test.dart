import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_builder_mobile/data/daily_plan/backend_daily_plan_enrich_api.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan.dart';

void main() {
  final plan = DailyPlan(
    userId: 'raw-user-id-must-not-leave-device',
    date: DateTime(2026, 8, 2),
    currentResin: 40,
    maxResin: 200,
    availableMinutes: 30,
    items: const [
      DailyPlanItem(
        id: 'wd_freedom',
        type: DailyPlanItemType.weekdayMaterial,
        title: '自由の導き',
        priority: 95,
        characterIds: ['10000002'],
        materialIds: ['104301'],
        estimatedResinCost: 20,
        estimatedMinutes: 20,
        availableToday: true,
        requiresResin: true,
        bookmarked: true,
        reasons: ['今日開放', '不足12個'],
      ),
      DailyPlanItem(
        id: 'talent_locked',
        type: DailyPlanItemType.talent,
        title: '天賦をLv.9へ',
        priority: 90,
        estimatedResinCost: 20,
        estimatedMinutes: 20,
        availableToday: false,
        requiresResin: true,
        reasons: ['本日は対象素材の開放日ではない'],
      ),
    ],
  );

  test('sends only bounded candidates and parses a validated proposal', () async {
    late Map<String, dynamic> sent;
    final api = BackendDailyPlanEnrichApi(
      baseUrl: 'https://builder.example.com',
      client: MockClient((request) async {
        expect(request.url.path, '/api/daily-plan/enrich');
        sent = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'ok': true,
              'data': {
                'summary': '今日は曜日素材を優先します',
                'recommendations': [
                  {
                    'taskId': 'wd_freedom',
                    'priority': 1,
                    'category': 'do_today',
                    'reason': '今日開放されているため',
                    'suggestedMinutes': 20,
                  },
                ],
                'deferredTaskIds': ['talent_locked'],
                'warnings': [],
                'source': 'deepseek',
                'generatedAt': '2026-08-02T03:00:00.000Z',
                'inputHash':
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                'modelIdentifier': 'deepseek-v4-flash',
              },
            }),
          ),
          200,
        );
      }),
    );

    final proposal = await api.suggest(
      plan: plan,
      weekday: 7,
      clientScope: '0123456789ab',
      force: true,
    );

    expect(proposal?.isAiGenerated, isTrue);
    expect(proposal?.recommendations.single.taskId, 'wd_freedom');
    expect(sent['clientScope'], '0123456789ab');
    expect(sent['force'], isTrue);
    expect(sent.toString(), isNot(contains(plan.userId)));
    expect(sent.toString().toLowerCase(), isNot(contains('cookie')));
    expect((sent['candidates'] as List).length, 2);
  });

  test(
    'rejects unknown fields, unknown ids, and unavailable recommendations',
    () async {
      Future<void> expectRejected(Map<String, dynamic> data) async {
        final api = BackendDailyPlanEnrichApi(
          baseUrl: 'https://builder.example.com',
          client: MockClient(
            (_) async => http.Response.bytes(
              utf8.encode(jsonEncode({'ok': true, 'data': data})),
              200,
            ),
          ),
        );
        expect(
          await api.suggest(
            plan: plan,
            weekday: 7,
            clientScope: '0123456789ab',
          ),
          isNull,
        );
      }

      Map<String, dynamic> payload(String taskId) => {
        'summary': '候補を選びました',
        'recommendations': [
          {
            'taskId': taskId,
            'priority': 1,
            'category': 'do_today',
            'reason': '構造化された理由',
            'suggestedMinutes': 20,
          },
        ],
        'deferredTaskIds': taskId == 'wd_freedom' ? ['talent_locked'] : [],
        'warnings': [],
        'source': 'deepseek',
        'generatedAt': '2026-08-02T03:00:00.000Z',
        'inputHash':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      };

      await expectRejected({...payload('wd_freedom'), 'rawAiOutput': 'secret'});
      await expectRejected(payload('invented'));
      await expectRejected(payload('talent_locked'));
    },
  );

  test('rejects unknown response-envelope fields', () async {
    final api = BackendDailyPlanEnrichApi(
      baseUrl: 'https://builder.example.com',
      client: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'ok': true,
              'data': {
                'summary': '候補を選びました',
                'recommendations': [
                  {
                    'taskId': 'wd_freedom',
                    'priority': 1,
                    'category': 'do_today',
                    'reason': '今日開放されているため',
                    'suggestedMinutes': 20,
                  },
                ],
                'deferredTaskIds': ['talent_locked'],
                'warnings': [],
                'source': 'deepseek',
                'generatedAt': '2026-08-02T03:00:00.000Z',
                'inputHash':
                    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
              },
              'raw': 'must not be accepted',
            }),
          ),
          200,
        ),
      ),
    );

    expect(
      await api.suggest(plan: plan, weekday: 7, clientScope: '0123456789ab'),
      isNull,
    );
  });

  test('rejects non-local HTTP backend URLs before sending data', () async {
    var called = false;
    final api = BackendDailyPlanEnrichApi(
      baseUrl: 'http://builder.example.com',
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    expect(
      await api.suggest(plan: plan, weekday: 7, clientScope: '0123456789ab'),
      isNull,
    );
    expect(called, isFalse);
  });
}
