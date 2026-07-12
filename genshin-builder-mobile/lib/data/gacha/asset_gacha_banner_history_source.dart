import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/gacha/gacha_banner_schedule.dart';

abstract class GachaBannerHistorySource {
  Future<GachaBannerSchedule> load();
}

class AssetGachaBannerHistorySource implements GachaBannerHistorySource {
  AssetGachaBannerHistorySource({
    AssetBundle? bundle,
    this.assetPath = 'assets/config/gacha_banner_history.json',
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String assetPath;

  @override
  Future<GachaBannerSchedule> load() async {
    final raw = await _bundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return GachaBannerSchedule.fromJson(decoded);
  }
}
