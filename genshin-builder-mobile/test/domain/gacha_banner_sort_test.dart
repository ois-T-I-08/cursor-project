import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/gacha/gacha_banner.dart';

GachaBanner _b({
  required String id,
  required DateTime start,
  required DateTime end,
  GachaBannerType type = GachaBannerType.character,
}) {
  return GachaBanner(
    id: id,
    type: type,
    name: id,
    version: '1.0',
    start: start,
    end: end,
  );
}

void main() {
  group('sortGachaBanners', () {
    final now = DateTime.utc(2024, 6, 15, 12);

    test('puts active before upcoming before ended', () {
      final ended = _b(
        id: 'ended',
        start: DateTime.utc(2024, 1, 1),
        end: DateTime.utc(2024, 1, 20),
      );
      final upcoming = _b(
        id: 'upcoming',
        start: DateTime.utc(2024, 7, 1),
        end: DateTime.utc(2024, 7, 20),
      );
      final active = _b(
        id: 'active',
        start: DateTime.utc(2024, 6, 1),
        end: DateTime.utc(2024, 6, 30),
      );

      final sorted = sortGachaBanners(
        [ended, upcoming, active],
        now: now,
      );
      expect(sorted.map((e) => e.id), ['active', 'upcoming', 'ended']);
    });

    test('orders active by nearest end first', () {
      final a = _b(
        id: 'ends-later',
        start: DateTime.utc(2024, 6, 1),
        end: DateTime.utc(2024, 6, 28),
      );
      final b = _b(
        id: 'ends-sooner',
        start: DateTime.utc(2024, 6, 1),
        end: DateTime.utc(2024, 6, 20),
      );
      final sorted = sortGachaBanners([a, b], now: now);
      expect(sorted.map((e) => e.id), ['ends-sooner', 'ends-later']);
    });

    test('orders ended by newest start first', () {
      final older = _b(
        id: 'older',
        start: DateTime.utc(2023, 1, 1),
        end: DateTime.utc(2023, 1, 20),
      );
      final newer = _b(
        id: 'newer',
        start: DateTime.utc(2024, 1, 1),
        end: DateTime.utc(2024, 1, 20),
      );
      final sorted = sortGachaBanners([older, newer], now: now);
      expect(sorted.map((e) => e.id), ['newer', 'older']);
    });
  });

  group('mergeGachaBanners', () {
    test('live overwrites same id', () {
      final history = [
        _b(
          id: 'live-1',
          start: DateTime.utc(2024, 6, 1),
          end: DateTime.utc(2024, 6, 20),
        ).copyWith(name: 'old'),
      ];
      final live = [
        _b(
          id: 'live-1',
          start: DateTime.utc(2024, 6, 1),
          end: DateTime.utc(2024, 6, 20),
        ).copyWith(name: 'new'),
      ];
      final merged = mergeGachaBanners(history: history, live: live);
      expect(merged, hasLength(1));
      expect(merged.single.name, 'new');
    });

    test('live replaces history with same schedule window', () {
      final history = [
        _b(
          id: 'character-5.0-1',
          start: DateTime.utc(2024, 6, 1),
          end: DateTime.utc(2024, 6, 20),
        ).copyWith(name: 'history'),
      ];
      final live = [
        _b(
          id: 'live-99',
          start: DateTime.utc(2024, 6, 1),
          end: DateTime.utc(2024, 6, 20),
        ).copyWith(name: 'live'),
      ];
      final merged = mergeGachaBanners(history: history, live: live);
      expect(merged, hasLength(1));
      expect(merged.single.id, 'live-99');
      expect(merged.single.name, 'live');
    });

    test('keeps history when live is empty', () {
      final history = [
        _b(
          id: 'h1',
          start: DateTime.utc(2020, 9, 28),
          end: DateTime.utc(2020, 10, 18),
        ),
      ];
      final merged = mergeGachaBanners(history: history, live: const []);
      expect(merged, hasLength(1));
      expect(merged.single.id, 'h1');
    });
  });
}
