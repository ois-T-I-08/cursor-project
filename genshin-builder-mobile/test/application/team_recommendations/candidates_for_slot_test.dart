import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/team_recommendations/candidates_for_slot.dart';
import 'package:genshin_builder_mobile/domain/team_recommendation/team_recommendation.dart';

TeamRecommendation _rec(
  List<String> members, {
  Map<String, List<String>> alternatives = const {},
}) {
  return TeamRecommendation(
    members: members,
    score: 0.9,
    simulationStatus: 'observed',
    sourceTypes: const ['aza'],
    rotationConfidence: 'medium',
    observedByAza: true,
    inputQuality: SimulationInputQuality.partial,
    reasons: const [],
    alternatives: alternatives,
  );
}

TeamSimulationJob _completed(List<TeamRecommendation> recommendations) {
  return TeamSimulationJob(
    jobId: 'job-1',
    status: TeamSimulationJobStatus.completed,
    result: TeamRecommendationResult(
      attackerId: 'A',
      generatedAt: DateTime(2026, 7, 1),
      engine: 'aza+rules',
      recommendations: recommendations,
    ),
  );
}

void main() {
  test('maps remaining members to empty slots left-to-right', () {
    final job = _completed([
      _rec(['A', 'B', 'C', 'D']),
      _rec(['A', 'B', 'E', 'F']),
    ]);
    final slots = <String?>['A', null, null, null];

    expect(candidatesForSlot(job: job, slotCharacterIds: slots, slotIndex: 1), [
      'B',
    ]);
    expect(candidatesForSlot(job: job, slotCharacterIds: slots, slotIndex: 2), [
      'C',
      'E',
    ]);
    expect(candidatesForSlot(job: job, slotCharacterIds: slots, slotIndex: 3), [
      'D',
      'F',
    ]);
  });

  test('skips already filled slots and excludes selected ids', () {
    final job = _completed([
      _rec(['A', 'B', 'C', 'D']),
    ]);
    final slots = <String?>['A', 'B', null, null];

    expect(
      candidatesForSlot(job: job, slotCharacterIds: slots, slotIndex: 1),
      isEmpty,
    );
    expect(candidatesForSlot(job: job, slotCharacterIds: slots, slotIndex: 2), [
      'C',
    ]);
    expect(candidatesForSlot(job: job, slotCharacterIds: slots, slotIndex: 3), [
      'D',
    ]);
  });

  test('includes alternatives for the primary candidate', () {
    final job = _completed([
      _rec(
        ['A', 'B', 'C', 'D'],
        alternatives: {
          'B': ['B2'],
          'C': ['C2'],
        },
      ),
    ]);
    final slots = <String?>['A', null, null, null];

    expect(candidatesForSlot(job: job, slotCharacterIds: slots, slotIndex: 1), [
      'B',
      'B2',
    ]);
    expect(candidatesForSlot(job: job, slotCharacterIds: slots, slotIndex: 2), [
      'C',
      'C2',
    ]);
  });

  test('returns empty when job incomplete or slot0 empty', () {
    expect(
      candidatesForSlot(
        job: const TeamSimulationJob(
          jobId: 'x',
          status: TeamSimulationJobStatus.running,
        ),
        slotCharacterIds: ['A', null, null, null],
        slotIndex: 1,
      ),
      isEmpty,
    );
    expect(
      candidatesForSlot(
        job: _completed([_rec(['A', 'B', 'C', 'D'])]),
        slotCharacterIds: [null, null, null, null],
        slotIndex: 1,
      ),
      isEmpty,
    );
  });

  test('applyRecommendationToEmptySlots fills only empties', () {
    expect(
      applyRecommendationToEmptySlots(
        current: ['A', null, 'X', null],
        members: ['A', 'B', 'C', 'D'],
      ),
      ['A', 'B', 'X', 'C'],
    );
  });
}
