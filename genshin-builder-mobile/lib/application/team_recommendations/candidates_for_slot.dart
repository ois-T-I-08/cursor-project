import '../../domain/team_recommendation/team_recommendation.dart';

/// Derives per-slot candidate character IDs from a completed recommendation job.
///
/// For each recommendation, members not already in [slotCharacterIds] are
/// packed left-to-right into empty slots. The character mapped to [slotIndex]
/// (plus its `alternatives` entries) becomes a candidate. Order follows
/// recommendation score order; duplicates are removed.
List<String> candidatesForSlot({
  required TeamSimulationJob? job,
  required List<String?> slotCharacterIds,
  required int slotIndex,
}) {
  if (job == null || job.status != TeamSimulationJobStatus.completed) {
    return const [];
  }
  final result = job.result;
  if (result == null) return const [];
  if (slotIndex < 0 || slotIndex >= slotCharacterIds.length) {
    return const [];
  }
  if (slotCharacterIds[slotIndex] != null) return const [];

  final selected = <String>{
    for (final id in slotCharacterIds)
      if (id != null) id,
  };
  if (selected.isEmpty) return const [];

  final emptyIndexes = <int>[
    for (var i = 0; i < slotCharacterIds.length; i++)
      if (slotCharacterIds[i] == null) i,
  ];
  final packedIndex = emptyIndexes.indexOf(slotIndex);
  if (packedIndex < 0) return const [];

  final seen = <String>{};
  final out = <String>[];

  void add(String id) {
    if (id.isEmpty || selected.contains(id) || !seen.add(id)) return;
    out.add(id);
  }

  for (final recommendation in result.recommendations) {
    final remaining = <String>[
      for (final id in recommendation.members)
        if (!selected.contains(id)) id,
    ];
    if (packedIndex >= remaining.length) continue;
    final primary = remaining[packedIndex];
    add(primary);
    final alts = recommendation.alternatives[primary];
    if (alts == null) continue;
    for (final alt in alts) {
      add(alt);
    }
  }
  return out;
}

/// Fills empty slots left-to-right with [members] not already selected.
/// Occupied slots are never overwritten.
List<String?> applyRecommendationToEmptySlots({
  required List<String?> current,
  required List<String> members,
}) {
  final next = List<String?>.from(current);
  final selected = <String>{
    for (final id in next)
      if (id != null) id,
  };
  final toPlace = <String>[
    for (final id in members)
      if (!selected.contains(id)) id,
  ];
  var memberIndex = 0;
  for (var i = 0; i < next.length && memberIndex < toPlace.length; i++) {
    if (next[i] != null) continue;
    final id = toPlace[memberIndex++];
    next[i] = id;
    selected.add(id);
  }
  return next;
}
