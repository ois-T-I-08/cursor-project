import 'dart:convert';

import 'package:flutter/services.dart';

import '../config/config_load_log.dart';
import '../config/config_validators.dart';
import 'artifact_score_weight.dart';
import 'artifact_score_weight_source.dart';

const _configKind = 'artifact_score_weights';

class LocalJsonArtifactScoreWeightSource implements ArtifactScoreWeightSource {
  LocalJsonArtifactScoreWeightSource({
    AssetBundle? bundle,
    this.assetPath = 'assets/config/artifact_score_weights.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String assetPath;
  List<ArtifactScoreWeightProfile>? _cache;

  @override
  Future<List<ArtifactScoreWeightProfile>> loadProfiles() async {
    if (_cache != null) return _cache!;
    late final String raw;
    try {
      raw = await _bundle.loadString(assetPath);
    } catch (_) {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.assetMissing,
      );
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.invalidJson,
      );
    }

    if (decoded is! Map) {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.invalidRootType,
      );
    }
    final map = Map<String, dynamic>.from(decoded);

    try {
      validateArtifactScoreWeightsJson(map);
    } on FormatException catch (e) {
      throw configLoadFromFormatException(kind: _configKind, error: e);
    }

    try {
      final items = (map['profiles'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(
            (e) => ArtifactScoreWeightProfile.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false);
      _cache = items;
      return items;
    } catch (_) {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.unexpected,
      );
    }
  }
}
