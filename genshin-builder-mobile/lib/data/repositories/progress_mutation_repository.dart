import 'package:uuid/uuid.dart';

import '../../domain/models/master_models.dart';
import '../../domain/history/growth_event.dart';
import '../../domain/account/account_snapshot.dart';
import '../../domain/repositories/progress_mutation_repository.dart'
    as domain;
import '../db/app_database_facade.dart';
import '../db/drift/daos/growth_dao.dart' show EventParams;
import '../../application/history/detect_growth_events_use_case.dart';

const _uuid = Uuid();

/// Coordinates UserProgress save and GrowthEvent generation in a single DB transaction.
class DriftProgressMutationRepository
    implements domain.ProgressMutationRepository {
  DriftProgressMutationRepository(this._db);
  final AppDatabase _db;

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
    final events = <GrowthEvent>[];
    final now = DateTime.now();

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
      await _db.upsertProgress(progress);
      if (events.isNotEmpty) {
        await dao.eventsSaveAll(events.map((e) => EventParams(
              eventId: _uuid.v4(),
              userId: e.userId,
              characterId: e.characterId,
              eventType: e.eventType.name,
              beforeValue: e.beforeValue,
              afterValue: e.afterValue,
              source: e.source,
              observedAt: e.observedAt.millisecondsSinceEpoch,
              dedupKey: e.dedupKey,
            )).toList());
      }
    });

    return events;
  }

  /// Build a simple CharacterSnapshot from UserProgress for diff detection.
  CharacterSnapshot _toSnapshot(UserProgress p, {bool isOwned = false}) {
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
      artifactCompletion: p.artifactCompleted ? 1.0 : 0.0,
      artifactCompletionAvailable: p.artifactCompleted,
    );
  }
}
