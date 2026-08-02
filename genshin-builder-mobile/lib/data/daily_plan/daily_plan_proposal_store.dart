import 'dart:convert';

import '../../domain/planning/daily_plan_proposal.dart';
import '../../domain/planning/daily_plan.dart';
import '../db/app_database_facade.dart';
import 'daily_plan_proposal_codec.dart';

class DailyPlanProposalStore {
  DailyPlanProposalStore(this._db);

  final AppDatabase _db;

  Future<DailyPlanProposal?> read({
    required String userScope,
    required String localDate,
    required String planFingerprint,
    required DailyPlan plan,
  }) async {
    final raw = await _db.getSetting(_key(userScope, localDate));
    if (raw == null || raw.isEmpty || raw.length > 32768) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map.length != 3 ||
          map['version'] != 1 ||
          map['planFingerprint'] != planFingerprint) {
        return null;
      }
      return parseDailyPlanProposal(map['proposal'], plan: plan);
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required String userScope,
    required String localDate,
    required String planFingerprint,
    required DailyPlanProposal proposal,
  }) {
    final encoded = jsonEncode({
      'version': 1,
      'planFingerprint': planFingerprint,
      'proposal': dailyPlanProposalToJson(proposal),
    });
    return _db.setSetting(_key(userScope, localDate), encoded);
  }

  Future<void> clear({required String userScope, required String localDate}) =>
      _db.setSetting(_key(userScope, localDate), '');

  String _key(String userScope, String localDate) =>
      'daily_plan_adopted_v1_${userScope}_$localDate';
}
