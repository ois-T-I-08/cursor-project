import '../../domain/account/account_snapshot.dart';
import '../../domain/account/snapshot_supplement.dart';
import '../../domain/artifact_completion.dart';
import '../../domain/artifact_score.dart';
import '../../domain/models/master_models.dart';
import '../../domain/planning/growth_goal.dart';
import '../../domain/repositories/character_repository.dart';
import '../../domain/repositories/growth_goal_repository.dart';
import '../../domain/repositories/material_inventory_repository.dart';
import '../../domain/repositories/progress_repository.dart';
import '../../domain/repositories/team_repository.dart';

/// Builds an [AccountSnapshot] from multiple repositories and optional HoYoLAB supplement.
class BuildAccountSnapshotUseCase {
  BuildAccountSnapshotUseCase({
    required this.characterRepo,
    required this.progressRepo,
    required this.goalRepo,
    required this.inventoryRepo,
    required this.teamRepo,
    required this.userId,
    this.supplement,
  });

  final CharacterRepository characterRepo;
  final ProgressRepository progressRepo;
  final GrowthGoalRepository goalRepo;
  final MaterialInventoryRepository inventoryRepo;
  final TeamRepository teamRepo;
  final String userId;
  final AccountSnapshotSupplement? supplement;

  Future<AccountSnapshot> call() async {
    final characters = await characterRepo.getAll();
    final progressList = await progressRepo.getAll(userId);
    final goals = await goalRepo.getAll(userId);
    final inventory = await inventoryRepo.getInventory(userId);
    final teams = await teamRepo.getAll(userId);
    final progressMap = {for (final p in progressList) p.characterId: p};
    final sources = <String>[
      'characterRepository',
      'progressRepository',
      'growthGoalRepository',
      'materialInventoryRepository',
      'teamRepository',
    ];

    if (supplement != null &&
        supplement!.status == SnapshotSupplementStatus.linked) {
      sources.add('hoyolabCache');
    }

    final snapshots = characters.map((mc) {
      final progress = progressMap[mc.id];
      final hoyoChar = supplement?.characters[mc.id];
      // Merge: HoYoLAB values override local if non-null
      final level = hoyoChar?.level ?? progress?.level ?? 1;
      final ascension = hoyoChar?.ascension ?? progress?.ascension ?? 0;
      final constellation =
          hoyoChar?.constellation ?? progress?.constellation ?? 0;
      final talentNormal =
          hoyoChar?.talentNormal ?? progress?.talentNormal ?? 1;
      final talentSkill = hoyoChar?.talentSkill ?? progress?.talentSkill ?? 1;
      final talentBurst = hoyoChar?.talentBurst ?? progress?.talentBurst ?? 1;
      final weaponId = hoyoChar?.weaponId ?? progress?.weaponId;
      final weaponName = hoyoChar?.weaponName ?? progress?.weaponName;
      final weaponLevel = hoyoChar?.weaponLevel ?? progress?.weaponLevel ?? 1;
      final weaponRefinement =
          hoyoChar?.weaponRefinement ?? progress?.weaponRefinement ?? 1;
      final localArtifact = _artifactCompletionFromProgress(progress);
      // Prefer character-detail completion % when local relic data exists.
      final artifactCompletionVal = localArtifact.available
          ? localArtifact.value
          : (hoyoChar?.artifactCompletion ?? localArtifact.value);
      final isOwned = progress != null || hoyoChar != null;

      return CharacterSnapshot(
        characterId: mc.id,
        name: mc.name,
        element: mc.element,
        weaponType: mc.weaponType,
        rarity: mc.rarity,
        region: mc.region,
        isOwned: isOwned,
        level: level,
        ascension: ascension,
        constellation: constellation,
        talentNormal: talentNormal,
        talentSkill: talentSkill,
        talentBurst: talentBurst,
        equippedWeaponId:
            weaponId != null && weaponId.isNotEmpty ? weaponId : null,
        equippedWeaponName:
            weaponName != null && weaponName.isNotEmpty ? weaponName : null,
        weaponLevel: weaponLevel,
        weaponRefinement: weaponRefinement,
        artifactCompletion: artifactCompletionVal,
        artifactCompletionAvailable:
            localArtifact.available || hoyoChar?.artifactCompletion != null,
        memo: progress?.memo,
      );
    }).toList();

    return AccountSnapshot(
      userId: userId,
      characters: snapshots,
      materialInventory: inventory,
      savedTeams: teams,
      activeGoals:
          goals.where((g) => g.status == GrowthGoalStatus.active).toList(),
      currentResin: supplement?.currentResin,
      maxResin: supplement?.maxResin,
      weekday: DateTime.now().weekday,
      acquiredAt: DateTime.now(),
      sources: sources,
    );
  }

  /// Same metric as character detail [ArtifactCompletionPanel] (0.0–1.0).
  ({double value, bool available}) _artifactCompletionFromProgress(
    UserProgress? progress,
  ) {
    if (progress == null) return (value: 0.0, available: false);
    final artifacts = progress.artifacts;
    final available = artifacts.values.any(isArtifactPieceEquipped);
    if (!available) return (value: 0.0, available: false);

    final scoreType = userArtifactScoreTypeFromStorage(progress.artifactScoreType) ??
        artifactScoreTypeFromString(progress.artifactScoreType) ??
        ArtifactScoreType.atk;
    final report = calcArtifactCompletionReport(
      artifacts,
      scoreType: scoreType,
      weights: scoreWeightsForType(scoreType),
    );
    return (value: (report.overallPercent / 100.0).clamp(0.0, 1.0), available: true);
  }
}
