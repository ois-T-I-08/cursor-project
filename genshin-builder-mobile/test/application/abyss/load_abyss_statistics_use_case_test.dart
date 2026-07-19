import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/application/abyss/load_abyss_statistics_use_case.dart';
import 'package:genshin_builder_mobile/domain/abyss/abyss_statistics.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/repositories/abyss_statistics_repository.dart';
import 'package:genshin_builder_mobile/domain/repositories/character_repository.dart';

import '../../support/abyss_statistics_fixture.dart';

void main() {
  test(
    'enriches AZA identifiers only from the local master repository',
    () async {
      final useCase = LoadAbyssStatisticsUseCase(
        statisticsRepository: _StatisticsRepository(sampleAbyssStatistics()),
        characterRepository: _CharacterRepository(),
        artifactSetNames: () async => const {'15020': '絶縁の旗印'},
      );

      final result = await useCase.execute();

      expect(result.characters.single.characterName, '雷電将軍');
      expect(
        result.characters.single.iconUrl,
        'https://example.com/raiden.png',
      );
      expect(result.characters.single.weapons.single.displayName, '草薙の稲光');
      expect(
        result.characters.single.artifacts.single.setPieces.single.displayName,
        '絶縁の旗印',
      );
      expect(result.teams.single.members.first.characterName, '雷電将軍');
      expect(result.teams.single.members[1].characterName, isNull);
    },
  );

  test(
    'propagates typed repository errors to the provider/UI boundary',
    () async {
      final useCase = LoadAbyssStatisticsUseCase(
        statisticsRepository: _StatisticsRepository.error(),
        characterRepository: _CharacterRepository(),
      );

      await expectLater(
        useCase.execute(),
        throwsA(
          isA<AbyssStatisticsException>().having(
            (error) => error.failure,
            'failure',
            AbyssStatisticsFailure.timeout,
          ),
        ),
      );
    },
  );
}

class _StatisticsRepository implements AbyssStatisticsRepository {
  _StatisticsRepository(this.statistics) : failure = null;

  _StatisticsRepository.error()
    : statistics = null,
      failure = AbyssStatisticsFailure.timeout;

  final AbyssStatistics? statistics;
  final AbyssStatisticsFailure? failure;

  @override
  Future<AbyssStatistics> fetchLatest() async {
    if (failure != null) throw AbyssStatisticsException(failure!);
    return statistics!;
  }
}

class _CharacterRepository implements CharacterRepository {
  @override
  Future<List<MasterCharacter>> getAll() async => const [
    MasterCharacter(
      id: '10000052',
      name: '雷電将軍',
      element: 'electric',
      weaponType: 'polearm',
      rarity: 5,
      region: 'Inazuma',
      iconUrl: 'https://example.com/raiden.png',
    ),
  ];

  @override
  Future<List<MasterWeapon>> getAllWeapons() async => const [
    MasterWeapon(
      id: '13509',
      name: '草薙の稲光',
      weaponType: 'polearm',
      rarity: 5,
      iconUrl: 'https://example.com/engulfing.png',
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
