import 'package:uuid/uuid.dart';
import '../../domain/history/growth_event.dart';
import '../../domain/account/account_snapshot.dart';

const _uuid = Uuid();

/// Detects growth events by comparing before/after [CharacterSnapshot] lists.
///
/// First sync is treated as a baseline (no events generated).
/// Subsequent syncs generate events for each material change.
class DetectGrowthEventsUseCase {
  const DetectGrowthEventsUseCase();

  /// Compare [before] and [after] snapshots and return new growth events.
  /// Pass [isInitialSync]=true if this is the first sync (baseline).
  List<GrowthEvent> call({
    required List<CharacterSnapshot> before,
    required List<CharacterSnapshot> after,
    required String userId,
    String source = 'sync',
    DateTime? observedAt,
    bool isInitialSync = false,
  }) {
    if (isInitialSync) return [];
    if (before.isEmpty) return [];

    final now = observedAt ?? DateTime.now();
    final events = <GrowthEvent>[];
    final afterMap = {for (final c in after) c.characterId: c};

    for (final prev in before) {
      final curr = afterMap[prev.characterId];
      if (curr == null) continue;

      _addIfChanged(
        events,
        userId,
        prev.characterId,
        GrowthEventType.characterLevelChanged,
        '${prev.level}',
        '${curr.level}',
        prev.level != curr.level,
        source,
        now,
      );
      _addIfChanged(
        events,
        userId,
        prev.characterId,
        GrowthEventType.ascensionChanged,
        '${prev.ascension}',
        '${curr.ascension}',
        prev.ascension != curr.ascension,
        source,
        now,
      );
      _addIfChanged(
        events,
        userId,
        prev.characterId,
        GrowthEventType.talentNormalChanged,
        '${prev.talentNormal}',
        '${curr.talentNormal}',
        prev.talentNormal != curr.talentNormal,
        source,
        now,
      );
      _addIfChanged(
        events,
        userId,
        prev.characterId,
        GrowthEventType.talentSkillChanged,
        '${prev.talentSkill}',
        '${curr.talentSkill}',
        prev.talentSkill != curr.talentSkill,
        source,
        now,
      );
      _addIfChanged(
        events,
        userId,
        prev.characterId,
        GrowthEventType.talentBurstChanged,
        '${prev.talentBurst}',
        '${curr.talentBurst}',
        prev.talentBurst != curr.talentBurst,
        source,
        now,
      );
      _addIfChanged(
        events,
        userId,
        prev.characterId,
        GrowthEventType.weaponChanged,
        prev.equippedWeaponId ?? '',
        curr.equippedWeaponId ?? '',
        prev.equippedWeaponId != curr.equippedWeaponId,
        source,
        now,
      );
      _addIfChanged(
        events,
        userId,
        prev.characterId,
        GrowthEventType.weaponLevelChanged,
        '${prev.weaponLevel}',
        '${curr.weaponLevel}',
        prev.weaponLevel != curr.weaponLevel,
        source,
        now,
      );
      _addIfChanged(
        events,
        userId,
        prev.characterId,
        GrowthEventType.weaponRefinementChanged,
        '${prev.weaponRefinement}',
        '${curr.weaponRefinement}',
        prev.weaponRefinement != curr.weaponRefinement,
        source,
        now,
      );
      _addIfChanged(
        events,
        userId,
        prev.characterId,
        GrowthEventType.artifactCompletionChanged,
        prev.artifactCompletion.toStringAsFixed(1),
        curr.artifactCompletion.toStringAsFixed(1),
        prev.artifactCompletion != curr.artifactCompletion,
        source,
        now,
      );
    }

    return events;
  }

  void _addIfChanged(
    List<GrowthEvent> events,
    String userId,
    String characterId,
    GrowthEventType type,
    String before,
    String after,
    bool changed,
    String source,
    DateTime observedAt,
  ) {
    if (!changed) return;
    events.add(
      GrowthEvent(
        eventId: _uuid.v4(),
        userId: userId,
        characterId: characterId,
        eventType: type,
        beforeValue: before,
        afterValue: after,
        source: source,
        observedAt: observedAt,
        dedupKey: GrowthEvent.makeValueDedupKey(
          userId: userId,
          characterId: characterId,
          eventType: type,
          before: before,
          after: after,
        ),
      ),
    );
  }
}
