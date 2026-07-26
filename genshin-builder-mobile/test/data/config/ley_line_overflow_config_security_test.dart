import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/config/config_validators.dart';
import 'package:genshin_builder_mobile/data/config/ley_line_overflow_repository.dart';
import 'package:genshin_builder_mobile/domain/planning/ley_line_overflow_catalog.dart';

Map<String, dynamic> _catalogJson({
  Object version = 1,
  List<Object?>? events,
}) => {
  'version': version,
  'defaults': {
    'displayName': '地脈の奔流',
    'eventType': 'leyLineOverflow',
    'dailyBonusLimit': 3,
    'rewardMultiplier': 2,
    'condensedResinEligible': false,
    'eligibleLeyLineTypes': ['exp', 'mora'],
    'nameMatchers': ['地脈の奔流', 'Ley Line Overflow'],
  },
  'events': events ?? <Object?>[],
};

Map<String, dynamic> _event({
  String id = 'event-1',
  Object startAt = '2026-07-01T00:00:00Z',
  Object endAt = '2026-07-08T09:00:00+09:00',
}) => {'eventId': id, 'startAt': startAt, 'endAt': endAt, 'enabled': true};

LeyLineOverflowCatalog _catalog(int version) => LeyLineOverflowCatalog(
  version: version,
  defaults: const LeyLineOverflowDefaults(
    displayName: '地脈の奔流',
    dailyBonusLimit: 3,
    nameMatchers: ['地脈の奔流'],
  ),
);

class _SequenceSource implements LeyLineOverflowCatalogSource {
  _SequenceSource(this.results);

  final List<Object> results;
  var index = 0;

  @override
  Future<LeyLineOverflowCatalog> load() async {
    final result = results[index++];
    if (result is Error) throw result;
    if (result is Exception) throw result;
    return result as LeyLineOverflowCatalog;
  }
}

void main() {
  group('Ley Line Overflow config validation', () {
    test('accepts bounded events with explicit timezone offsets', () {
      expect(
        () =>
            validateLeyLineOverflowEventsJson(_catalogJson(events: [_event()])),
        returnsNormally,
      );
    });

    test('rejects fractional or non-positive versions', () {
      for (final version in [0, -1, 1.5]) {
        expect(
          () =>
              validateLeyLineOverflowEventsJson(_catalogJson(version: version)),
          throwsFormatException,
        );
      }
    });

    test('rejects duplicate event IDs', () {
      expect(
        () => validateLeyLineOverflowEventsJson(
          _catalogJson(events: [_event(), _event()]),
        ),
        throwsFormatException,
      );
    });

    test('rejects timezone-less and reversed event windows', () {
      for (final event in [
        _event(startAt: '2026-07-01T00:00:00'),
        _event(startAt: '2026-07-08T00:00:00Z', endAt: '2026-07-01T00:00:00Z'),
        _event(startAt: '2026-07-01T00:00:00Z', endAt: '2026-07-01T00:00:00Z'),
      ]) {
        expect(
          () =>
              validateLeyLineOverflowEventsJson(_catalogJson(events: [event])),
          throwsFormatException,
        );
      }
    });

    test('rejects unbounded event and matcher lists', () {
      expect(
        () => validateLeyLineOverflowEventsJson(
          _catalogJson(events: List.generate(129, (i) => _event(id: 'e$i'))),
        ),
        throwsFormatException,
      );
      final json = _catalogJson();
      (json['defaults'] as Map<String, dynamic>)['nameMatchers'] =
          List.generate(33, (i) => 'matcher-$i');
      expect(
        () => validateLeyLineOverflowEventsJson(json),
        throwsFormatException,
      );
    });
  });

  group('CompositeLeyLineOverflowCatalogSource', () {
    test('uses the last known good remote catalog after a failure', () async {
      final source = CompositeLeyLineOverflowCatalogSource(
        localSource: _SequenceSource([_catalog(1), _catalog(1)]),
        remoteSource: _SequenceSource([
          _catalog(2),
          StateError('temporary remote failure'),
        ]),
      );

      expect((await source.load()).version, 2);
      expect((await source.load()).version, 2);
    });

    test(
      'does not replace the last known good catalog with an older one',
      () async {
        final source = CompositeLeyLineOverflowCatalogSource(
          localSource: _SequenceSource([_catalog(1), _catalog(1)]),
          remoteSource: _SequenceSource([_catalog(3), _catalog(2)]),
        );

        expect((await source.load()).version, 3);
        expect((await source.load()).version, 3);
      },
    );
  });
}
