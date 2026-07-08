import 'dart:convert';

/// 聖遺物の部位
enum ArtifactSlotKey { flower, plume, sands, goblet, circlet }

/// サブステータス1行
class ArtifactSubstat {
  const ArtifactSubstat({required this.stat, required this.value});

  final String stat;
  final double value;

  Map<String, dynamic> toJson() => {'stat': stat, 'value': value};

  factory ArtifactSubstat.fromJson(Map<String, dynamic> json) => ArtifactSubstat(
        stat: json['stat'] as String? ?? '',
        value: (json['value'] as num?)?.toDouble() ?? 0,
      );

  ArtifactSubstat copyWith({String? stat, double? value}) => ArtifactSubstat(
        stat: stat ?? this.stat,
        value: value ?? this.value,
      );
}

/// 聖遺物1部位
class ArtifactPiece {
  const ArtifactPiece({
    this.setName = '',
    this.mainStat = '',
    this.level = 0,
    this.substats = const [],
  });

  final String setName;
  final String mainStat;
  final int level;
  final List<ArtifactSubstat> substats;

  Map<String, dynamic> toJson() => {
        'setName': setName,
        'mainStat': mainStat,
        'level': level,
        'substats': substats.map((s) => s.toJson()).toList(),
      };

  factory ArtifactPiece.fromJson(Map<String, dynamic> json) => ArtifactPiece(
        setName: json['setName'] as String? ?? json['setId'] as String? ?? '',
        mainStat: json['mainStat'] as String? ?? '',
        level: json['level'] as int? ?? 0,
        substats: (json['substats'] as List<dynamic>? ?? [])
            .map((e) => ArtifactSubstat.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  ArtifactPiece copyWith({
    String? setName,
    String? mainStat,
    int? level,
    List<ArtifactSubstat>? substats,
  }) =>
      ArtifactPiece(
        setName: setName ?? this.setName,
        mainStat: mainStat ?? this.mainStat,
        level: level ?? this.level,
        substats: substats ?? this.substats,
      );
}

typedef ArtifactState = Map<ArtifactSlotKey, ArtifactPiece>;

ArtifactPiece createEmptyArtifactPiece({String mainStat = ''}) =>
    ArtifactPiece(mainStat: mainStat);

ArtifactState createEmptyArtifactState() => {
      ArtifactSlotKey.flower: createEmptyArtifactPiece(mainStat: 'HP'),
      ArtifactSlotKey.plume: createEmptyArtifactPiece(mainStat: '攻撃力'),
      ArtifactSlotKey.sands: createEmptyArtifactPiece(),
      ArtifactSlotKey.goblet: createEmptyArtifactPiece(),
      ArtifactSlotKey.circlet: createEmptyArtifactPiece(),
    };

ArtifactState parseArtifactState(String? json) {
  if (json == null || json.trim().isEmpty) {
    return createEmptyArtifactState();
  }
  try {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final empty = createEmptyArtifactState();
    for (final slot in ArtifactSlotKey.values) {
      final raw = decoded[slot.name] as Map<String, dynamic>?;
      if (raw != null) {
        empty[slot] = ArtifactPiece.fromJson(raw);
      }
    }
    return empty;
  } catch (_) {
    return createEmptyArtifactState();
  }
}

String encodeArtifactState(ArtifactState state) {
  final map = {for (final e in state.entries) e.key.name: e.value.toJson()};
  return jsonEncode(map);
}

ArtifactState copyArtifactState(ArtifactState state) => {
      for (final e in state.entries) e.key: e.value,
    };

ArtifactState updateArtifactPiece(
  ArtifactState state,
  ArtifactSlotKey slot,
  ArtifactPiece piece,
) {
  final next = copyArtifactState(state);
  next[slot] = piece;
  return next;
}
