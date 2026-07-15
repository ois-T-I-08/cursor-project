import 'dart:convert';

import '../../domain/team/team_models.dart';
import '../../domain/repositories/team_repository.dart';
import '../db/app_database_facade.dart';

class DriftTeamRepository implements TeamRepository {
  DriftTeamRepository(this._db);
  final AppDatabase _db;

  static const _version = 1;

  @override
  Future<List<Team>> getAll(String userId) async {
    final rows = await _db.growthDao.teamsGetAll(userId);
    final teams = <Team>[];
    for (final row in rows) {
      try {
        final team = _toTeam(row);
        teams.add(team);
      } catch (_) {
        // Skip individually malformed teams; don't fail the whole list
      }
    }
    return teams;
  }

  @override
  Future<Team?> getById(String id) async {
    final row = await _db.growthDao.teamGetById(id);
    if (row == null) return null;
    try {
      return _toTeam(row);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String userId, Team team) async {
    // Validate team constraints before saving
    final error = Team.validate(team);
    if (error != null) throw ArgumentError(error);

    final membersJson = jsonEncode({
      'version': _version,
      'members': team.members.map((m) => {
            'characterId': m.characterId,
            'buildId': m.buildId,
            'position': m.position,
          }).toList(),
    });
    await _db.growthDao.teamSave(
      id: team.id,
      userId: userId,
      name: team.name,
      membersJson: membersJson,
      notes: team.notes,
    );
  }

  @override
  Future<void> delete(String id) => _db.growthDao.teamDelete(id);

  Team _toTeam(dynamic row) {
    final raw = row.membersJson as String;
    if (raw.isEmpty) throw const FormatException('Empty members JSON');

    dynamic parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (e) {
      throw FormatException('Invalid JSON in saved team: $e');
    }

    // Handle both v1 format ({"version":1, "members":[...]}) and legacy (plain [...]).
    List membersList;
    if (parsed is Map) {
      membersList = parsed['members'] as List? ?? [];
    } else if (parsed is List) {
      membersList = parsed;
    } else {
      throw FormatException('Unexpected members JSON type: ${parsed.runtimeType}');
    }

    final members = membersList.map((m) {
      if (m is! Map) throw const FormatException('Member entry is not a Map');
      final cid = m['characterId'];
      if (cid is! String || cid.isEmpty) throw const FormatException('Missing characterId');
      return TeamMemberSlot(
        characterId: cid,
        buildId: m['buildId'] as String?,
        position: (m['position'] as int?) ?? 0,
      );
    }).toList();

    final team = Team(
      id: row.id as String,
      name: row.name as String,
      members: members,
      notes: row.notes as String? ?? '',
    );

    // Re-validate after parse
    final error = Team.validate(team);
    if (error != null) throw FormatException(error);

    return team;
  }
}
