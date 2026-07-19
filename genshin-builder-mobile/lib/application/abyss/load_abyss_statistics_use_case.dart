import '../../domain/abyss/abyss_statistics.dart';
import '../../domain/repositories/abyss_statistics_repository.dart';
import '../../domain/repositories/character_repository.dart';

class LoadAbyssStatisticsUseCase {
  const LoadAbyssStatisticsUseCase({
    required AbyssStatisticsRepository statisticsRepository,
    required CharacterRepository characterRepository,
  }) : _statisticsRepository = statisticsRepository,
       _characterRepository = characterRepository;

  final AbyssStatisticsRepository _statisticsRepository;
  final CharacterRepository _characterRepository;

  Future<AbyssStatistics> execute() async {
    final statistics = await _statisticsRepository.fetchLatest();
    final characters = await _characterRepository.getAll();
    final weapons = await _characterRepository.getAllWeapons();
    final characterById = {for (final item in characters) item.id: item};
    final weaponById = {for (final item in weapons) item.id: item};

    return statistics.copyWith(
      characters: [
        for (final item in statistics.characters)
          item.copyWith(
            characterName: characterById[item.characterId]?.name,
            iconUrl: characterById[item.characterId]?.iconUrl,
            weapons: [
              for (final weapon in item.weapons)
                weapon.copyWith(displayName: weaponById[weapon.id]?.name),
            ],
          ),
      ],
      teams: [
        for (final team in statistics.teams)
          team.copyWith(
            members: [
              for (final member in team.members)
                member.copyWith(
                  characterName: characterById[member.characterId]?.name,
                  iconUrl: characterById[member.characterId]?.iconUrl,
                ),
            ],
          ),
      ],
    );
  }
}
