import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../domain/models/master_models.dart';
import '../../domain/history/growth_event.dart';
import '../../domain/account/account_snapshot.dart';
import '../../domain/artifact_completion.dart';
import '../../domain/artifact_score.dart';
import '../../domain/repositories/progress_mutation_repository.dart' as domain;
import '../db/app_database_facade.dart';
import '../db/drift/daos/growth_dao.dart' show EventParams;
import '../../application/history/detect_growth_events_use_case.dart';

const _uuid = Uuid();

enum ProgressMutationPoint {
  beforeProgressWrite,
  afterProgressWrite,
  beforeEventsWrite,
  afterEventsWrite,
  beforeCommit,
}

typedef ProgressMutationFaultHook =
    FutureOr<void> Function(ProgressMutationPoint point);

/// Coordinates UserProgress save and GrowthEvent generation in a single DB transaction.
class DriftProgressMutationRepository
    implements domain.ProgressMutationRepository {
  DriftProgressMutationRepository(
    this._db, {
    ProgressMutationFaultHook? faultHook,
    DateTime Function()? now,
    String Function()? eventId,
  }) : _faultHook = faultHook,
       _now = now ?? DateTime.now,
       _eventId = eventId ?? _uuid.v4;

  final AppDatabase _db;
  final ProgressMutationFaultHook? _faultHook;
  final DateTime Function() _now;
  final String Function() _eventId;

  /// Save progress and optionally generate growth events.
  /// [before] is the previous progress snapshot (null = baseline/no events).
  /// Returns the list of events generated (empty if none).
  @override
  Future<List<GrowthEvent>> saveWithEvents({
    required UserProgress progress,
    required String userId,
    UserProgress? before,
    String source = 'localManual',
  }) async {
    if (progress.userId != userId ||
        (before != null && before.userId != userId)) {
      throw ArgumentError.value(userId, 'userId', 'Progress owner mismatch');
    }

    final events = <GrowthEvent>[];
    final now = _now();

    // Build after-snapshot for diff detection
    final after = _toSnapshot(progress, isOwned: true);

    if (before != null) {
      final detected = const DetectGrowthEventsUseCase()(
        before: [_toSnapshot(before, isOwned: true)],
        after: [after],
        userId: userId,
        source: source,
        isInitialSync: false,
        observedAt: now,
      );
      events.addAll(detected);
    }

    // Execute progress save + event inserts in transaction
    final dao = _db.growthDao;
    final dbTx = _db;
    await dbTx.transaction(() async {
      await _checkpoint(ProgressMutationPoint.beforeProgressWrite);
      await _db.upsertProgress(progress);
      await _checkpoint(ProgressMutationPoint.afterProgressWrite);
      if (events.isNotEmpty) {
        await _checkpoint(ProgressMutationPoint.beforeEventsWrite);
        await dao.eventsSaveAll(
          events
              .map(
                (e) => EventParams(
                  eventId: _eventId(),
                  userId: e.userId,
                  characterId: e.characterId,
                  eventType: e.eventType.name,
                  beforeValue: e.beforeValue,
                  afterValue: e.afterValue,
                  source: e.source,
                  observedAt: e.observedAt.millisecondsSinceEpoch,
                  dedupKey: e.dedupKey,
                ),
              )
              .toList(),
        );
        await _checkpoint(ProgressMutationPoint.afterEventsWrite);
      }
      await _checkpoint(ProgressMutationPoint.beforeCommit);
    });

    return events;
  }

  Future<void> _checkpoint(ProgressMutationPoint point) async {
    await _faultHook?.call(point);
  }

  /// Build a simple CharacterSnapshot from UserProgress for diff detection.
  CharacterSnapshot _toSnapshot(UserProgress p, {bool isOwned = false}) {
    final completion = _artifactCompletion(p);
    return CharacterSnapshot(
      characterId: p.characterId,
      name: '',
      element: '',
      weaponType: '',
      rarity: 0,
      region: '',
      isOwned: isOwned,
      level: p.level,
      ascension: p.ascension,
      constellation: p.constellation,
      talentNormal: p.talentNormal,
      talentSkill: p.talentSkill,
      talentBurst: p.talentBurst,
      equippedWeaponId: p.weaponId.isNotEmpty ? p.weaponId : null,
      equippedWeaponName: p.weaponName.isNotEmpty ? p.weaponName : null,
      weaponLevel: p.weaponLevel,
      weaponRefinement: p.weaponRefinement,
      artifactCompletion: completion.value,
      artifactCompletionAvailable: completion.available,
    );
  }

  /// Same metric as character detail artifact completion panel (0.0–1.0).
  ({double value, bool available}) _artifactCompletion(UserProgress p) {
    final artifacts = p.artifacts;
    final available = artifacts.values.any(isArtifactPieceEquipped);
    if (!available) return (value: 0.0, available: false);
    final scoreType = userArtifactScoreTypeFromStorage(p.artifactScoreType) ??
        artifactScoreTypeFromString(p.artifactScoreType) ??
        ArtifactScoreType.atk;
    final report = calcArtifactCompletionReport(
      artifacts,
      scoreType: scoreType,
      weights: scoreWeightsForType(scoreType),
    );
    return (
      value: (report.overallPercent / 100.0).clamp(0.0, 1.0),
      available: true,
    );
  }
}
