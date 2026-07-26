import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/planning/resin_farm_cost_table.dart';
import '../config/config_load_log.dart';
import '../config/config_validators.dart';

const _configKind = 'resin_farm_costs';

abstract class ResinFarmCostSource {
  Future<ResinFarmCostTable> load();
}

class LocalJsonResinFarmCostSource implements ResinFarmCostSource {
  LocalJsonResinFarmCostSource({
    AssetBundle? bundle,
    this.assetPath = 'assets/config/resin_farm_costs.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String assetPath;
  ResinFarmCostTable? _cache;

  @override
  Future<ResinFarmCostTable> load() async {
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
      validateResinFarmCostsJson(map);
    } on FormatException catch (e) {
      throw configLoadFromFormatException(kind: _configKind, error: e);
    }

    try {
      _cache = ResinFarmCostTable.fromJson(map);
      return _cache!;
    } catch (_) {
      throw const ConfigLoadException(
        kind: _configKind,
        failure: ConfigLoadFailureKind.unexpected,
      );
    }
  }
}

class ResinFarmCostRepository {
  ResinFarmCostRepository(this._source);

  final ResinFarmCostSource _source;

  Future<ResinFarmCostTable> getTable() => _source.load();
}
