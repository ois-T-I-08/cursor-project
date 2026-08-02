/// 編成（将来のチームシミュレーター用ドメインモデル）。
/// UI 未接続。既存の1キャラ進捗とは独立。
library;

class TeamMemberSlot {
  const TeamMemberSlot({
    required this.characterId,
    this.buildId,
    this.position = 0,
  });

  final String characterId;
  final String? buildId;
  final int position;
}

class Team {
  const Team({
    required this.id,
    required this.name,
    this.members = const [],
    this.notes = '',
  });

  final String id;
  final String name;
  final List<TeamMemberSlot> members;
  final String notes;

  int get size => members.length;

  bool get isFull => members.length >= 4;

  static const maxSize = 4;

  /// Validates team constraints. Returns null if valid, or an error message.
  static String? validate(Team team) {
    if (team.id.isEmpty) {
      return 'Team id must not be empty';
    }
    if (team.name.isEmpty) {
      return 'Team name must not be empty';
    }
    if (team.members.length > maxSize) {
      return 'Team cannot have more than $maxSize members';
    }
    final ids = <String>{};
    for (final m in team.members) {
      if (m.characterId.isEmpty) {
        return 'Member characterId must not be empty';
      }
      if (!ids.add(m.characterId)) {
        return 'Duplicate character ${m.characterId} in team';
      }
    }
    return null;
  }

  Team copyWith({
    String? id,
    String? name,
    List<TeamMemberSlot>? members,
    String? notes,
  }) => Team(
    id: id ?? this.id,
    name: name ?? this.name,
    members: members ?? this.members,
    notes: notes ?? this.notes,
  );
}
