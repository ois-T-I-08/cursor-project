import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_builder_mobile/application/abyss/load_abyss_statistics_use_case.dart';
import 'package:genshin_builder_mobile/domain/abyss/abyss_statistics.dart';
import 'package:genshin_builder_mobile/domain/models/master_models.dart';
import 'package:genshin_builder_mobile/domain/repositories/abyss_statistics_repository.dart';
import 'package:genshin_builder_mobile/domain/repositories/character_repository.dart';
import 'package:genshin_builder_mobile/providers/abyss_statistics_providers.dart';

import '../support/abyss_statistics_fixture.dart';

void main() {
  test('abyssStatisticsProvider resolves the normal use-case result', () async {
    final container = _container(_Repository(sampleAbyssStatistics()));
    addTearDown(container.dispose);

    final result = await container.read(abyssStatisticsProvider.future);

    expect(result.metadata.source, AbyssDataSource.aza);
    expect(result.characters.single.usageRate, 0.876);
  });

  test('abyssStatisticsProvider preserves a typed failure', () async {
    final container = _container(_Repository.error());
    addTearDown(container.dispose);

    await expectLater(
      container.read(abyssStatisticsProvider.future),
      throwsA(
        isA<AbyssStatisticsException>().having(
          (error) => error.failure,
          'failure',
          AbyssStatisticsFailure.networkError,
        ),
      ),
    );
  });
}

ProviderContainer _container(AbyssStatisticsRepository repository) {
  final useCase = LoadAbyssStatisticsUseCase(
    statisticsRepository: repository,
    characterRepository: _CharacterRepository(),
  );
  return ProviderContainer(
    overrides: [
      loadAbyssStatisticsUseCaseProvider.overrideWith((ref) async => useCase),
    ],
  );
}

class _Repository implements AbyssStatisticsRepository {
  _Repository(this.statistics) : failure = null;

  _Repository.error()
    : statistics = null,
      failure = AbyssStatisticsFailure.networkError;

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
  Future<List<MasterCharacter>> getAll() async => const [];

  @override
  Future<List<MasterWeapon>> getAllWeapons() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
