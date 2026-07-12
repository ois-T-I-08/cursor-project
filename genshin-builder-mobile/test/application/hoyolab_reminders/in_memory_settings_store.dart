import 'package:genshin_builder_mobile/data/hoyolab/hoyolab_home_disk_cache.dart';

class InMemoryHoyolabSettingsStore implements HoyolabSettingsStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getSetting(String key) async => values[key];

  @override
  Future<void> setSetting(String key, String value) async {
    values[key] = value;
  }
}
