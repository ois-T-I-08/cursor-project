import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/data/hoyolab/models/daily_note.dart';

void main() {
  group('DailyNote.fromJson', () {
    test('parses resin, daily tasks, expeditions', () {
      final note = DailyNote.fromJson({
        'current_resin': 120,
        'max_resin': 160,
        'resin_recovery_time': '3600',
        'finished_task_num': 3,
        'total_task_num': 4,
        'current_home_coin': 100,
        'max_home_coin': 2400,
        'expeditions': [
          {'status': 'Finished', 'remaining_time': '0'},
          {'status': 'Ongoing', 'remaining_time': '1800'},
        ],
      });

      expect(note.currentResin, 120);
      expect(note.remainingResin, 40);
      expect(note.dailyTasksComplete, isFalse);
      expect(note.finishedExpeditions, 1);
      expect(note.activeExpeditions, 1);
      expect(note.hasMaxResinFromApi, isTrue);
      expect(note.expeditions.first.hasRemainingTimeFromApi, isTrue);
    });
  });
}
