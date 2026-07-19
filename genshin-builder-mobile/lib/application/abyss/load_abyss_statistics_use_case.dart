import '../../domain/abyss/abyss_statistics.dart';
import '../../domain/repositories/abyss_statistics_repository.dart';
import '../../domain/repositories/character_repository.dart';

/// 聖遺物セット ID → 表示名（ローカル Amber マスタ由来）
typedef ArtifactSetNameLookup = Future<Map<String, String>> Function();

class LoadAbyssStatisticsUseCase {
  const LoadAbyssStatisticsUseCase({
    required AbyssStatisticsRepository statisticsRepository,
    required CharacterRepository characterRepository,
    ArtifactSetNameLookup? artifactSetNames,
  }) : _statisticsRepository = statisticsRepository,
       _characterRepository = characterRepository,
       _artifactSetNames = artifactSetNames;

  final AbyssStatisticsRepository _statisticsRepository;
  final CharacterRepository _characterRepository;
  final ArtifactSetNameLookup? _artifactSetNames;

  Future<AbyssStatistics> execute() async {
    final statistics = await _statisticsRepository.fetchLatest();
    final characters = await _characterRepository.getAll();
    final weapons = await _characterRepository.getAllWeapons();
    final artifactSetById = await _artifactSetNames?.call() ?? const {};
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
            artifacts: [
              for (final artifact in item.artifacts)
                artifact.copyWith(
                  setPieces: [
                    for (final piece in artifact.setPieces)
                      piece.copyWith(
                        displayName: artifactSetById[piece.artifactSetId],
                      ),
                  ],
                ),
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
