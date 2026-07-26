/// 樹脂ファーミング種類ごとのコスト表（設定 JSON の正本）。
library;

enum ResinFarmKind {
  talentDomain,
  weaponDomain,
  artifactDomain,
  weeklyBoss,
  worldBoss,
  leyLineExp,
  leyLineMora,
  zeroResin,
  unknown,
}

class ResinFarmKindCost {
  const ResinFarmKindCost({
    required this.resinPerRun,
    this.assumedDropsPerRun,
    this.assumedDropsPerRunMin,
    this.assumedDropsPerRunMax,
    this.assumedMoraPerRun,
    this.assumedHeroWitEquivalentPerRun,
    this.challengesPerWeek,
    this.contentLabel,
  });

  final int resinPerRun;
  final double? assumedDropsPerRun;
  final double? assumedDropsPerRunMin;
  final double? assumedDropsPerRunMax;
  final int? assumedMoraPerRun;
  final double? assumedHeroWitEquivalentPerRun;
  final int? challengesPerWeek;
  final String? contentLabel;

  bool get hasDropRange =>
      assumedDropsPerRunMin != null &&
      assumedDropsPerRunMax != null &&
      assumedDropsPerRunMin! > 0 &&
      assumedDropsPerRunMax! > 0;
}

class ResinFarmCostMeta {
  const ResinFarmCostMeta({
    this.naturalResinPerDay = 180,
    this.condensedResinValue = 40,
    this.synthesisRatio = 3,
    this.weekdayLabels = const ['月', '火', '水', '木', '金', '土', '日'],
  });

  final int naturalResinPerDay;
  final int condensedResinValue;
  final int synthesisRatio;
  final List<String> weekdayLabels;
}

class ResinFarmCostTable {
  const ResinFarmCostTable({
    required this.version,
    required this.kinds,
    this.zeroResinCategories = const {},
    this.meta = const ResinFarmCostMeta(),
  });

  final int version;
  final Map<ResinFarmKind, ResinFarmKindCost> kinds;
  final Set<String> zeroResinCategories;
  final ResinFarmCostMeta meta;

  ResinFarmKindCost? costFor(ResinFarmKind kind) => kinds[kind];

  factory ResinFarmCostTable.fromJson(Map<String, dynamic> json) {
    final kindsRaw = Map<String, dynamic>.from(json['kinds'] as Map);

    ResinFarmKindCost parseKind(String key) {
      final map = Map<String, dynamic>.from(kindsRaw[key] as Map);
      return ResinFarmKindCost(
        resinPerRun: (map['resinPerRun'] as num).toInt(),
        assumedDropsPerRun: (map['assumedDropsPerRun'] as num?)?.toDouble(),
        assumedDropsPerRunMin:
            (map['assumedDropsPerRunMin'] as num?)?.toDouble(),
        assumedDropsPerRunMax:
            (map['assumedDropsPerRunMax'] as num?)?.toDouble(),
        assumedMoraPerRun: (map['assumedMoraPerRun'] as num?)?.toInt(),
        assumedHeroWitEquivalentPerRun:
            (map['assumedHeroWitEquivalentPerRun'] as num?)?.toDouble(),
        challengesPerWeek: (map['challengesPerWeek'] as num?)?.toInt(),
        contentLabel: map['contentLabel'] as String?,
      );
    }

    final kinds = <ResinFarmKind, ResinFarmKindCost>{
      ResinFarmKind.talentDomain: parseKind('talentDomain'),
      ResinFarmKind.weaponDomain: parseKind('weaponDomain'),
      ResinFarmKind.artifactDomain: parseKind('artifactDomain'),
      ResinFarmKind.weeklyBoss: parseKind('weeklyBoss'),
      ResinFarmKind.worldBoss: parseKind('worldBoss'),
      ResinFarmKind.leyLineExp: parseKind('leyLineExp'),
      ResinFarmKind.leyLineMora: parseKind('leyLineMora'),
    };

    final zeroRaw = json['zeroResinCategories'] as List? ?? const [];
    final zero = <String>{
      for (final e in zeroRaw)
        if ('$e'.trim().isNotEmpty) '$e'.trim(),
    };

    var meta = const ResinFarmCostMeta();
    final metaRaw = json['meta'];
    if (metaRaw is Map) {
      final m = Map<String, dynamic>.from(metaRaw);
      final labels = m['weekdayLabels'];
      meta = ResinFarmCostMeta(
        naturalResinPerDay:
            (m['naturalResinPerDay'] as num?)?.toInt() ?? 180,
        condensedResinValue:
            (m['condensedResinValue'] as num?)?.toInt() ?? 40,
        synthesisRatio: (m['synthesisRatio'] as num?)?.toInt() ?? 3,
        weekdayLabels: labels is List && labels.length == 7
            ? [for (final e in labels) '$e']
            : const ['月', '火', '水', '木', '金', '土', '日'],
      );
    }

    return ResinFarmCostTable(
      version: (json['version'] as num).toInt(),
      kinds: kinds,
      zeroResinCategories: zero,
      meta: meta,
    );
  }
}
