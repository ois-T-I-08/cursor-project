// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:genshin_builder_mobile/data/config/config_validators.dart';

/// ローカル assets/config JSON をバリデーションする CLI。
///
/// ```bash
/// dart run tool/validate_config_json.dart
/// ```
void main(List<String> args) {
  final root = Directory.current.path;
  final checks =
      <({String path, void Function(Map<String, dynamic>) validate})>[
        (
          path: 'assets/config/artifact_score_weights.json',
          validate: validateArtifactScoreWeightsJson,
        ),
        (
          path: 'assets/config/daily_material_schedule.json',
          validate: validateDailyMaterialScheduleJson,
        ),
        (
          path: 'assets/config/resin_farm_costs.json',
          validate: validateResinFarmCostsJson,
        ),
        (
          path: 'assets/config/ley_line_overflow_events.json',
          validate: validateLeyLineOverflowEventsJson,
        ),
      ];

  var failed = false;
  for (final check in checks) {
    final file = File('$root/${check.path}');
    if (!file.existsSync()) {
      stderr.writeln('MISSING ${check.path}');
      failed = true;
      continue;
    }
    try {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      check.validate(decoded);
      stdout.writeln('OK ${check.path}');
    } catch (e) {
      stderr.writeln('FAIL ${check.path}: $e');
      failed = true;
    }
  }

  if (failed) {
    exit(1);
  }
}
