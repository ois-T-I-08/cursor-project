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
      throw FormatException('daily_material_schedule: $key must be a list');
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
  if (version is! int || version < 1) {
    throw const FormatException(
      'ley_line_overflow_events: version must be a positive integer',
    );
  }
  final defaults = json['defaults'];
  if (defaults is! Map) {
    throw const FormatException(
      'ley_line_overflow_events: defaults must be an object',
    );
  }
  final d = Map<String, dynamic>.from(defaults);
  _validateLeyLineString(
    d['displayName'],
    path: 'defaults.displayName',
    maxLength: 128,
  );
  if (d.containsKey('eventType')) {
    _validateLeyLineString(
      d['eventType'],
      path: 'defaults.eventType',
      maxLength: 64,
    );
  }
  final limit = d['dailyBonusLimit'];
  if (limit is! int || limit < 0) {
    throw const FormatException(
      'ley_line_overflow_events: defaults.dailyBonusLimit must be an integer >= 0',
    );
  }
  final multiplier = d['rewardMultiplier'];
  if (multiplier != null && (multiplier is! int || multiplier < 2)) {
    throw const FormatException(
      'ley_line_overflow_events: defaults.rewardMultiplier must be an integer >= 2',
    );
  }
  final condensed = d['condensedResinEligible'];
  if (condensed != null && condensed != false) {
    throw const FormatException(
      'ley_line_overflow_events: condensedResinEligible must be false',
    );
  }
  final matchers = d['nameMatchers'];
  if (matchers is! List || matchers.isEmpty || matchers.length > 32) {
    throw const FormatException(
      'ley_line_overflow_events: defaults.nameMatchers must contain 1-32 items',
    );
  }
  final seenMatchers = <String>{};
  for (var i = 0; i < matchers.length; i++) {
    final matcher = matchers[i];
    _validateLeyLineString(
      matcher,
      path: 'defaults.nameMatchers[$i]',
      maxLength: 128,
    );
    if (!seenMatchers.add((matcher as String).trim())) {
      throw FormatException(
        'ley_line_overflow_events: defaults.nameMatchers[$i] is duplicated',
      );
    }
  }
  if (d.containsKey('eligibleLeyLineTypes')) {
    _validateLeyLineTypes(
      d['eligibleLeyLineTypes'],
      path: 'defaults.eligibleLeyLineTypes',
    );
  }
  final events = json['events'];
  if (events != null && events is! List) {
    throw const FormatException(
      'ley_line_overflow_events: events must be a list',
    );
  }
  if (events is! List) return;
  if (events.length > 128) {
    throw const FormatException(
      'ley_line_overflow_events: events must contain at most 128 items',
    );
  }

  final eventIds = <String>{};
  for (var i = 0; i < events.length; i++) {
    final raw = events[i];
    if (raw is! Map) {
      throw FormatException(
        'ley_line_overflow_events: events[$i] must be an object',
      );
    }
    final event = Map<String, dynamic>.from(raw);
    _validateLeyLineString(
      event['eventId'],
      path: 'events[$i].eventId',
      maxLength: 128,
    );
    final eventId = (event['eventId'] as String).trim();
    if (!eventIds.add(eventId)) {
      throw FormatException(
        'ley_line_overflow_events: events[$i].eventId is duplicated',
      );
    }

    final start = _validateLeyLineTimestamp(
      event['startAt'],
      path: 'events[$i].startAt',
    );
    final end = _validateLeyLineTimestamp(
      event['endAt'],
      path: 'events[$i].endAt',
    );
    if (!end.isAfter(start)) {
      throw FormatException(
        'ley_line_overflow_events: events[$i].endAt must be after startAt',
      );
    }

    for (final entry in const <(String, int)>[
      ('eventType', 64),
      ('displayName', 128),
      ('source', 128),
    ]) {
      if (event.containsKey(entry.$1)) {
        _validateLeyLineString(
          event[entry.$1],
          path: 'events[$i].${entry.$1}',
          maxLength: entry.$2,
        );
      }
    }
    final enabled = event['enabled'];
    if (enabled != null && enabled is! bool) {
      throw FormatException(
        'ley_line_overflow_events: events[$i].enabled must be a boolean',
      );
    }
    final eventLimit = event['dailyBonusLimit'];
    if (eventLimit != null && (eventLimit is! int || eventLimit < 0)) {
      throw FormatException(
        'ley_line_overflow_events: events[$i].dailyBonusLimit must be an integer >= 0',
      );
    }
    final eventMultiplier = event['rewardMultiplier'];
    if (eventMultiplier != null &&
        (eventMultiplier is! int || eventMultiplier < 2)) {
      throw FormatException(
        'ley_line_overflow_events: events[$i].rewardMultiplier must be an integer >= 2',
      );
    }
    if (event.containsKey('eligibleLeyLineTypes')) {
      _validateLeyLineTypes(
        event['eligibleLeyLineTypes'],
        path: 'events[$i].eligibleLeyLineTypes',
      );
    }
    if (event.containsKey('updatedAt')) {
      _validateLeyLineTimestamp(
        event['updatedAt'],
        path: 'events[$i].updatedAt',
      );
    }
  }
}

void _validateLeyLineString(
  Object? value, {
  required String path,
  required int maxLength,
}) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.trim().length > maxLength) {
    throw FormatException(
      'ley_line_overflow_events: $path must be a non-empty string up to $maxLength characters',
    );
  }
}

DateTime _validateLeyLineTimestamp(Object? value, {required String path}) {
  if (value is! String ||
      !RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value.trim())) {
    throw FormatException(
      'ley_line_overflow_events: $path must include a UTC offset',
    );
  }
  final parsed = DateTime.tryParse(value.trim());
  if (parsed == null) {
    throw FormatException(
      'ley_line_overflow_events: $path must be an ISO-8601 timestamp',
    );
  }
  return parsed.toUtc();
}

void _validateLeyLineTypes(Object? value, {required String path}) {
  if (value is! List || value.isEmpty || value.length > 2) {
    throw FormatException(
      'ley_line_overflow_events: $path must contain 1-2 items',
    );
  }
  const allowed = {'exp', 'mora', 'leyLineExp', 'leyLineMora'};
  final seen = <String>{};
  for (var i = 0; i < value.length; i++) {
    final item = value[i];
    if (item is! String || !allowed.contains(item) || !seen.add(item)) {
      throw FormatException(
        'ley_line_overflow_events: $path[$i] is invalid or duplicated',
      );
    }
  }
}
