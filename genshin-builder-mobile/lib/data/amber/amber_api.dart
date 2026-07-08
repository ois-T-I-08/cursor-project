import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/master_models.dart';
import 'amber_constants.dart';

class AmberApi {
  AmberApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const name = 'project-amber';

  Future<Map<String, dynamic>> _fetchMap(String path) async {
    final uri = Uri.parse('$amberBaseUrl$path');
    final response = await _client.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Amber API error: ${response.statusCode} $path');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['response'] != 200) {
      throw Exception('Amber API response error: $path');
    }
    return json['data'] as Map<String, dynamic>;
  }

  Future<List<MasterCharacter>> fetchCharacters() async {
    final data = await _fetchMap('/avatar');
    return data.entries.map((entry) {
      final raw = entry.value as Map<String, dynamic>;
      final element = raw['element'] as String?;
      return MasterCharacter(
        id: entry.key,
        name: raw['name'] as String? ?? entry.key,
        element: element != null ? (elementMap[element] ?? element.toLowerCase()) : 'anemo',
        weaponType: weaponTypeMap[raw['weaponType'] as String? ?? ''] ?? 'sword',
        rarity: (raw['rank'] as num?)?.toInt() ?? 4,
        region: regionMap[raw['region'] as String? ?? ''] ?? raw['region'] as String? ?? '',
        iconUrl: buildIconUrl(raw['icon'] as String? ?? ''),
        scoreType: 'atk',
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<List<MasterWeapon>> fetchWeapons() async {
    final data = await _fetchMap('/weapon');
    return data.entries.map((entry) {
      final raw = entry.value as Map<String, dynamic>;
      return MasterWeapon(
        id: entry.key,
        name: raw['name'] as String? ?? entry.key,
        weaponType: weaponTypeMap[raw['type'] as String? ?? ''] ?? 'sword',
        rarity: (raw['rank'] as num?)?.toInt() ?? 3,
        iconUrl: buildIconUrl(raw['icon'] as String? ?? ''),
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<List<MasterMaterial>> fetchMaterials() async {
    final data = await _fetchMap('/material');
    return data.entries
        .map((entry) {
          final raw = entry.value as Map<String, dynamic>;
          final type = raw['type'] as String? ?? '';
          if (!materialCategories.contains(type)) return null;
          return MasterMaterial(
            id: entry.key,
            name: raw['name'] as String? ?? entry.key,
            category: type,
            rarity: (raw['rank'] as num?)?.toInt(),
            iconUrl: buildIconUrl(raw['icon'] as String? ?? ''),
          );
        })
        .whereType<MasterMaterial>()
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<Map<String, dynamic>> fetchAvatarDetail(String id) async {
    return _fetchMap('/avatar/$id');
  }

  Future<Map<String, dynamic>> fetchWeaponDetail(String id) async {
    return _fetchMap('/weapon/$id');
  }

  void dispose() => _client.close();
}
