/// リモート / ローカル設定 JSON の最低限バリデーション。
/// 失敗時は [FormatException] を投げ、composite source がフォールバックできるようにする。
library;

void validateArtifactScoreWeightsJson(Map<String, dynamic> json) {
  final profiles = json['profiles'];
  if (profiles is! List || profiles.isEmpty) {
    throw const FormatException(
      'artifact_score_weights: profiles must be a non-empty list',
    );
  }
  for (var i = 0; i < profiles.length; i++) {
    final item = profiles[i];
    if (item is! Map) {
      throw FormatException(
        'artifact_score_weights: profiles[$i] must be an object',
      );
    }
    final map = Map<String, dynamic>.from(item);
    final characterId = '${map['characterId'] ?? ''}'.trim();
    if (characterId.isEmpty) {
      throw FormatException(
        'artifact_score_weights: profiles[$i].characterId is required',
      );
    }
    final weights = map['weights'];
    if (weights is! Map) {
      throw FormatException(
        'artifact_score_weights: profiles[$i].weights is required',
      );
    }
  }
}

void validateDailyMaterialScheduleJson(Map<String, dynamic> json) {
  final version = json['version'];
  if (version is! num) {
    throw const FormatException(
      'daily_material_schedule: version must be a number',
    );
  }

  void validateSeries(String key, {bool required = true}) {
    final list = json[key];
    if (list == null) {
      if (required) {
        throw FormatException(
          'daily_material_schedule: $key must be a non-empty list',
        );
      }
      return;
    }
    if (list is! List) {
      throw FormatException(
        'daily_material_schedule: $key must be a list',
      );
    }
    if (required && list.isEmpty) {
      throw FormatException(
        'daily_material_schedule: $key must be a non-empty list',
      );
    }
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      if (item is! Map) {
        throw FormatException(
          'daily_material_schedule: $key[$i] must be an object',
        );
      }
      final map = Map<String, dynamic>.from(item);
      final id = '${map['id'] ?? ''}'.trim();
      if (id.isEmpty) {
        throw FormatException(
          'daily_material_schedule: $key[$i].id is required',
        );
      }
      final materialIds = map['materialIds'];
      if (materialIds is! List || materialIds.isEmpty) {
        throw FormatException(
          'daily_material_schedule: $key[$i].materialIds must be non-empty',
        );
      }
      for (final mid in materialIds) {
        if ('$mid'.trim().isEmpty) {
          throw FormatException(
            'daily_material_schedule: $key[$i].materialIds contains empty id',
          );
        }
      }
      final days = map['days'];
      if (days is! List || days.isEmpty) {
        throw FormatException(
          'daily_material_schedule: $key[$i].days must be non-empty',
        );
      }
      for (final d in days) {
        final day = d is num ? d.toInt() : int.tryParse('$d');
        if (day == null || day < 1 || day > 7) {
          throw FormatException(
            'daily_material_schedule: $key[$i].days must be 1–7 (got $d)',
          );
        }
      }
    }
  }

  validateSeries('talentSeries');
  validateSeries('weaponSeries');
  validateSeries('artifactSeries', required: false);
  validateSeries('weeklyBossSeries', required: false);
}

void validateResinFarmCostsJson(Map<String, dynamic> json) {
  final version = json['version'];
  if (version is! num) {
    throw const FormatException('resin_farm_costs: version must be a number');
  }
  final kinds = json['kinds'];
  if (kinds is! Map) {
    throw const FormatException('resin_farm_costs: kinds must be an object');
  }
  final kindsMap = Map<String, dynamic>.from(kinds);
  const requiredKinds = <String>[
    'talentDomain',
    'weaponDomain',
    'artifactDomain',
    'weeklyBoss',
    'worldBoss',
    'leyLineExp',
    'leyLineMora',
  ];
  for (final key in requiredKinds) {
    final entry = kindsMap[key];
    if (entry is! Map) {
      throw FormatException('resin_farm_costs: kinds.$key must be an object');
    }
    final map = Map<String, dynamic>.from(entry);
    final resin = map['resinPerRun'];
    if (resin is! num || resin < 0) {
      throw FormatException(
        'resin_farm_costs: kinds.$key.resinPerRun must be >= 0',
      );
    }
    if (key == 'leyLineMora') {
      final mora = map['assumedMoraPerRun'];
      if (mora is! num || mora <= 0) {
        throw FormatException(
          'resin_farm_costs: kinds.$key.assumedMoraPerRun must be > 0',
        );
      }
    } else if (key == 'leyLineExp') {
      final hero = map['assumedHeroWitEquivalentPerRun'];
      final drops = map['assumedDropsPerRun'];
      if ((hero is! num || hero <= 0) && (drops is! num || drops <= 0)) {
        throw FormatException(
          'resin_farm_costs: kinds.$key needs assumedHeroWitEquivalentPerRun or assumedDropsPerRun',
        );
      }
    } else {
      final drops = map['assumedDropsPerRun'];
      if (drops is! num || drops <= 0) {
        throw FormatException(
          'resin_farm_costs: kinds.$key.assumedDropsPerRun must be > 0',
        );
      }
    }
  }
  final zero = json['zeroResinCategories'];
  if (zero != null) {
    if (zero is! List) {
      throw const FormatException(
        'resin_farm_costs: zeroResinCategories must be a list',
      );
    }
    for (var i = 0; i < zero.length; i++) {
      if ('${zero[i]}'.trim().isEmpty) {
        throw FormatException(
          'resin_farm_costs: zeroResinCategories[$i] must be non-empty',
        );
      }
    }
  }
}

void validateLeyLineOverflowEventsJson(Map<String, dynamic> json) {
  final version = json['version'];
  if (version is! num) {
    throw const FormatException(
      'ley_line_overflow_events: version must be a number',
    );
  }
  final defaults = json['defaults'];
  if (defaults is! Map) {
    throw const FormatException(
      'ley_line_overflow_events: defaults must be an object',
    );
  }
  final d = Map<String, dynamic>.from(defaults);
  final displayName = '${d['displayName'] ?? ''}'.trim();
  if (displayName.isEmpty) {
    throw const FormatException(
      'ley_line_overflow_events: defaults.displayName must be non-empty',
    );
  }
  final limit = d['dailyBonusLimit'];
  if (limit is! num || limit < 0) {
    throw const FormatException(
      'ley_line_overflow_events: defaults.dailyBonusLimit must be >= 0',
    );
  }
  final multiplier = d['rewardMultiplier'];
  if (multiplier != null && (multiplier is! num || multiplier < 2)) {
    throw const FormatException(
      'ley_line_overflow_events: defaults.rewardMultiplier must be >= 2',
    );
  }
  final condensed = d['condensedResinEligible'];
  if (condensed != null && condensed != false) {
    throw const FormatException(
      'ley_line_overflow_events: condensedResinEligible must be false',
    );
  }
  final matchers = d['nameMatchers'];
  if (matchers is! List || matchers.isEmpty) {
    throw const FormatException(
      'ley_line_overflow_events: defaults.nameMatchers must be a non-empty list',
    );
  }
  for (var i = 0; i < matchers.length; i++) {
    if ('${matchers[i]}'.trim().isEmpty) {
      throw FormatException(
        'ley_line_overflow_events: defaults.nameMatchers[$i] must be non-empty',
      );
    }
  }
  final events = json['events'];
  if (events != null && events is! List) {
    throw const FormatException(
      'ley_line_overflow_events: events must be a list',
    );
  }
}
