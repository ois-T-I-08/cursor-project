import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/gacha/gacha_calendar_api.dart';
import 'package:genshin_builder_mobile/domain/gacha/calendar_event.dart';
import 'package:genshin_builder_mobile/domain/gacha/gacha_banner.dart';
import 'package:genshin_builder_mobile/domain/gacha/gacha_banner_schedule.dart';

void main() {
  group('parseCalendarBanner', () {
    test('maps character event and featured rarities', () {
      final banner = parseCalendarBanner({
        'id': 194,
        'name': 'キャラクター祈願',
        'version': '6.7',
        'start_time': 1782860400,
        'end_time': 1784627940,
        'characters': [
          {
            'id': 10000133,
            'name': 'サンドローネ',
            'icon': 'https://example.com/a.png',
            'rarity': 5,
          },
          {
            'id': 10000024,
            'name': '北斗',
            'icon': 'https://example.com/b.png',
            'rarity': 4,
          },
        ],
        'weapons': [],
      });

      expect(banner.id, 'live-194');
      expect(banner.type, GachaBannerType.character);
      expect(banner.version, '6.7');
      expect(banner.featured5Ids, ['10000133']);
      expect(banner.featured4Ids, ['10000024']);
      expect(banner.sourceIcons['10000133'], 'https://example.com/a.png');
    });

    test('detects weapon and chronicled from name', () {
      expect(
        parseCalendarBanner({
          'id': 1,
          'name': '武器祈願',
          'version': '6.7',
          'start_time': 1,
          'end_time': 2,
          'characters': [],
          'weapons': [
            {'id': 12516, 'name': '超越の鍵', 'icon': '', 'rarity': 5},
          ],
        }).type,
        GachaBannerType.weapon,
      );
      expect(
        parseCalendarBanner({
          'id': 2,
          'name': '集録祈願/追憶祈願',
          'version': '6.7',
          'start_time': 1,
          'end_time': 2,
          'characters': [],
          'weapons': [],
        }).type,
        GachaBannerType.chronicled,
      );
    });
  });

  group('parseCalendarEvent', () {
    test('parses event with rewards and schedule', () {
      final event = parseCalendarEvent({
        'id': 333,
        'name': '幽境の激戦',
        'description': '説明文',
        'type_name': 'ActTypeHardChallenge',
        'start_time': 1783476000,
        'end_time': 1786391999,
        'image_url': null,
        'rewards': [
          {
            'id': 105006,
            'name': '聖啓の塵',
            'icon': 'https://example.com/r.png',
            'rarity': '5',
            'amount': 3,
          },
        ],
        'special_reward': {
          'id': 201,
          'name': '原石',
          'icon': 'https://example.com/p.png',
          'rarity': '5',
          'amount': 450,
        },
      });

      expect(event.name, '幽境の激戦');
      expect(event.hasSchedule, isTrue);
      expect(event.rewards, hasLength(1));
      expect(event.specialReward?.name, '原石');
      expect(event.specialReward?.amount, 450);
    });

    test('treats zero timestamps as no schedule', () {
      final event = parseCalendarEvent({
        'id': 1,
        'name': '期間未定',
        'description': '',
        'type_name': 'ActTypeOther',
        'start_time': 0,
        'end_time': 0,
        'rewards': [],
        'special_reward': null,
      });
      expect(event.hasSchedule, isFalse);
    });
  });

  group('sortCalendarEventsForHome', () {
    test('keeps active then upcoming and drops unscheduled', () {
      final now = DateTime.utc(2026, 7, 12, 3);
      final active = CalendarEvent(
        id: 'a',
        name: 'active',
        description: '',
        typeName: '',
        start: now.subtract(const Duration(days: 1)),
        end: now.add(const Duration(days: 2)),
      );
      final upcoming = CalendarEvent(
        id: 'u',
        name: 'upcoming',
        description: '',
        typeName: '',
        start: now.add(const Duration(days: 1)),
        end: now.add(const Duration(days: 5)),
      );
      final none = CalendarEvent(
        id: 'n',
        name: 'none',
        description: '',
        typeName: '',
        start: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        end: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      final sorted = sortCalendarEventsForHome(
        [none, upcoming, active],
        now: now,
      );
      expect(sorted.map((e) => e.id), ['a', 'u']);
    });
  });

  group('GachaBannerSchedule', () {
    test('parses asset-shaped json', () {
      final schedule = GachaBannerSchedule.fromJson({
        'version': 1,
        'banners': [
          {
            'id': 'character-1.0-0',
            'type': 'character',
            'name': 'Ballad in Goblets',
            'version': '1.0',
            'start': '2020-09-28T00:00:00+08:00',
            'end': '2020-10-18T18:00:00+08:00',
            'featured5Ids': ['10000022'],
            'featured4Ids': ['10000014'],
            'featuredWeaponIds': [],
          },
        ],
      });
      expect(schedule.banners, hasLength(1));
      expect(schedule.banners.single.featured5Ids, ['10000022']);
      expect(schedule.banners.single.start.isUtc, isTrue);
    });
  });
}
