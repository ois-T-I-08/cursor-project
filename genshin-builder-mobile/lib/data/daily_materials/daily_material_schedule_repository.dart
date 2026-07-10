import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/daily_materials/daily_material_models.dart';

abstract class DailyMaterialScheduleSource {
  Future<DailyMaterialSchedule> load();
}

class LocalJsonDailyMaterialScheduleSource
    implements DailyMaterialScheduleSource {
  LocalJsonDailyMaterialScheduleSource({
    AssetBundle? bundle,
    this.assetPath = 'assets/config/daily_material_schedule.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String assetPath;
  DailyMaterialSchedule? _cache;

  @override
  Future<DailyMaterialSchedule> load() async {
    if (_cache != null) return _cache!;
    final raw = await _bundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _cache = DailyMaterialSchedule.fromJson(decoded);
    return _cache!;
  }
}

class DailyMaterialScheduleRepository {
  DailyMaterialScheduleRepository(this._source);

  final DailyMaterialScheduleSource _source;

  Future<DailyMaterialSchedule> getSchedule() => _source.load();
}
