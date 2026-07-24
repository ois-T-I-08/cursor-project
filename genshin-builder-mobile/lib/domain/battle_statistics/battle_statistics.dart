import '../models/master_models.dart';

enum BattleStatsContentType { abyss, stygian }

enum RemoteBattleStatsState {
  current,
  updateAvailable,
  syncing,
  valid,
  invalid,
  unsupportedSchema,
  stale,
  offlineUsingCache,
}

enum BattleMemberAvailability { ready, owned, underbuilt, missing, unknown }

enum BattleTeamAvailability {
  ready,
  needsBuild,
  missingOne,
  partial,
  unavailable,
}

class BattleStatsManifestItem {
  const BattleStatsManifestItem({
    required this.contentType,
    required this.seasonId,
    required this.revision,
    required this.payloadHash,
    required this.updatedAt,
  });

  final BattleStatsContentType contentType;
  final String seasonId;
  final int revision;
  final String payloadHash;
  final DateTime updatedAt;
}

class BattleStatsManifest {
  const BattleStatsManifest({
    required this.schemaVersion,
    required this.items,
    this.etag,
  });

  final int schemaVersion;
  final Map<BattleStatsContentType, BattleStatsManifestItem> items;
  final String? etag;
}

class RemoteBattleTeam {
  const RemoteBattleTeam({
    required this.teamKey,
    required this.members,
    required this.usageRate,
    this.usageCount,
    this.rank,
    this.side,
    this.stageKey,
    this.sampleSize,
  });

  final String teamKey;
  final List<String> members;
  final double usageRate;
  final int? usageCount;
  final int? rank;
  final String? side;
  final String? stageKey;
  final int? sampleSize;
}

class RemoteBattleCharacterUsage {
  const RemoteBattleCharacterUsage({
    required this.characterId,
    required this.usageRate,
    this.usageCount,
    this.rank,
    this.side,
    this.ownershipRate,
    this.usageAmongOwnersRate,
    this.sampleSize,
  });

  final String characterId;
  final double usageRate;
  final int? usageCount;
  final int? rank;
  final String? side;
  final double? ownershipRate;
  final double? usageAmongOwnersRate;
  final int? sampleSize;
}

class BattleStatsBundle {
  const BattleStatsBundle({
    required this.schemaVersion,
    required this.contentType,
    required this.sourceVersion,
    required this.seasonId,
    required this.revision,
    required this.payloadHash,
    required this.sourceUpdatedAt,
    required this.teams,
    required this.characters,
    this.sampleSize,
  });

  final int schemaVersion;
  final BattleStatsContentType contentType;
  final String sourceVersion;
  final String seasonId;
  final int revision;
  final String payloadHash;
  final DateTime sourceUpdatedAt;
  final int? sampleSize;
  final List<RemoteBattleTeam> teams;
  final List<RemoteBattleCharacterUsage> characters;
}

class BattleMemberAssessment {
  const BattleMemberAssessment({
    required this.characterId,
    required this.availability,
  });

  final String characterId;
  final BattleMemberAvailability availability;
}

class BattleTeamAssessment {
  const BattleTeamAssessment({
    required this.availability,
    required this.members,
  });

  final BattleTeamAvailability availability;
  final List<BattleMemberAssessment> members;
}

/// 統計上の使用率とは分離し、端末内の所持・育成情報だけで利用可能性を判定する。
class BattleTeamAvailabilityEvaluator {
  const BattleTeamAvailabilityEvaluator();

  BattleTeamAssessment evaluate({
    required RemoteBattleTeam team,
    required Set<String> knownCharacterIds,
    required Map<String, UserProgress> progressByCharacterId,
  }) {
    final members = team.members
        .map((characterId) {
          if (!knownCharacterIds.contains(characterId)) {
            return BattleMemberAssessment(
              characterId: characterId,
              availability: BattleMemberAvailability.unknown,
            );
          }
          final progress = progressByCharacterId[characterId];
          if (progress == null) {
            return BattleMemberAssessment(
              characterId: characterId,
              availability: BattleMemberAvailability.missing,
            );
          }
          if (_isReady(progress)) {
            return BattleMemberAssessment(
              characterId: characterId,
              availability: BattleMemberAvailability.ready,
            );
          }
          final hasBuild =
              progress.level > 1 ||
              progress.ascension > 0 ||
              progress.talentNormal > 1 ||
              progress.talentSkill > 1 ||
              progress.talentBurst > 1 ||
              progress.weaponId.isNotEmpty ||
              _hasArtifactConfiguration(progress);
          return BattleMemberAssessment(
            characterId: characterId,
            availability:
                hasBuild
                    ? BattleMemberAvailability.underbuilt
                    : BattleMemberAvailability.owned,
          );
        })
        .toList(growable: false);

    final ready =
        members
            .where(
              (member) => member.availability == BattleMemberAvailability.ready,
            )
            .length;
    final missing =
        members
            .where(
              (member) =>
                  member.availability == BattleMemberAvailability.missing ||
                  member.availability == BattleMemberAvailability.unknown,
            )
            .length;
    final owned = members.length - missing;
    final availability = switch ((ready, missing, owned)) {
      (4, 0, _) => BattleTeamAvailability.ready,
      (_, 0, 4) => BattleTeamAvailability.needsBuild,
      (_, 1, _) => BattleTeamAvailability.missingOne,
      (_, _, 0) => BattleTeamAvailability.unavailable,
      _ => BattleTeamAvailability.partial,
    };
    return BattleTeamAssessment(availability: availability, members: members);
  }

  bool _isReady(UserProgress progress) {
    final developedTalents =
        [
          progress.talentNormal,
          progress.talentSkill,
          progress.talentBurst,
        ].where((level) => level >= 6).length;
    return progress.level >= 80 &&
        progress.ascension >= 5 &&
        developedTalents >= 2 &&
        progress.weaponId.isNotEmpty &&
        progress.weaponLevel >= 80 &&
        _hasArtifactConfiguration(progress);
  }

  bool _hasArtifactConfiguration(UserProgress progress) {
    if (progress.artifactCompleted) return true;
    return progress.artifacts.values
            .where(
              (piece) => piece.setName.trim().isNotEmpty || piece.level > 0,
            )
            .length >=
        5;
  }
}
