import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/domain/planning/daily_plan_completion_evaluator.dart';

void main() {
  const evaluator = DailyPlanCompletionEvaluator();

  test('empty plan → incomplete 0 / not notify candidate', () {
    expect(
      evaluator.countIncomplete(
        planItemKeys: const [],
        completedItemKeys: {'stale'},
      ),
      0,
    );
    expect(
      evaluator.shouldNotifyCandidate(
        planItemKeys: const [],
        completedItemKeys: const {},
      ),
      isFalse,
    );
  });

  test('all completed → not notify candidate', () {
    expect(
      evaluator.countIncomplete(
        planItemKeys: ['a', 'b'],
        completedItemKeys: {'a', 'b', 'extra'},
      ),
      0,
    );
    expect(
      evaluator.shouldNotifyCandidate(
        planItemKeys: ['a', 'b'],
        completedItemKeys: {'a', 'b'},
      ),
      isFalse,
    );
  });

  test('vanished items do not count as incomplete', () {
    expect(
      evaluator.countIncomplete(
        planItemKeys: ['a'],
        completedItemKeys: {'gone'},
      ),
      1,
    );
    expect(
      evaluator.countIncomplete(
        planItemKeys: ['a'],
        completedItemKeys: {'a', 'gone'},
      ),
      0,
    );
  });

  test('new items count as incomplete', () {
    expect(
      evaluator.countIncomplete(
        planItemKeys: ['old', 'new'],
        completedItemKeys: {'old'},
      ),
      1,
    );
    expect(
      evaluator.shouldNotifyCandidate(
        planItemKeys: ['old', 'new'],
        completedItemKeys: {'old'},
      ),
      isTrue,
    );
  });

  test('stale completion keys do not break current plan', () {
    expect(
      evaluator.countIncomplete(
        planItemKeys: ['a', 'b'],
        completedItemKeys: {'legacy1', 'legacy2'},
      ),
      2,
    );
  });
}
