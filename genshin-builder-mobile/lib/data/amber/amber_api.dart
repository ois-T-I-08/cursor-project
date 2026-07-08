import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/master_models.dart';
import 'amber_constants.dart';

class AmberApi {
  AmberApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const name = 'project-amber';
  static const _apiPrefix = '/api/v2/jp';

  Future<Map<String, dynamic>> _fetchItems(String path) async {
    final uri = Uri.parse('$amberBaseUrl$_apiPrefix$path');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Amber API error: ${response.statusCode} $path');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['response'] != 200) {
      throw Exception('Amber API response error: $path');
    }
    final data = json['data'] as Map<String, dynamic>;
    return data['items'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _fetchDetail(String path) async {
    final uri = Uri.parse('$amberBaseUrl$_apiPrefix$path');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 30));
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
    final items = await _fetchItems('/avatar');
    final characters = <MasterCharacter>[];

    for (final raw in items.values) {
      final avatar = raw as Map<String, dynamic>;
      final elementKey = avatar['element'] as String?;
      final element =
          elementKey != null ? elementMap[elementKey] : null;
      final name = avatar['name'] as String?;
      if (element == null || name == null || name.isEmpty) continue;

      final id = '${avatar['id']}';
      if (id.startsWith('10000007-')) continue;

      final isTraveler = id.startsWith('10000005-');
      final displayName = isTraveler
          ? '旅人（${elementLabelMap[element] ?? element}）'
          : name;

      characters.add(
        MasterCharacter(
          id: id,
          name: displayName,
          element: element,
          weaponType:
              weaponTypeMap[avatar['weaponType'] as String? ?? ''] ?? 'sword',
          rarity: (avatar['rank'] as num?)?.toInt() == 4 ? 4 : 5,
          region: regionMap[avatar['region'] as String? ?? ''] ??
              avatar['region'] as String? ??
              '',
          iconUrl: buildIconUrl(avatar['icon'] as String? ?? ''),
          scoreType: 'atk',
        ),
      );
    }

    characters.sort((a, b) => a.name.compareTo(b.name));
    return characters;
  }

  Future<List<MasterWeapon>> fetchWeapons() async {
    final items = await _fetchItems('/weapon');
    final weapons = <MasterWeapon>[];

    for (final raw in items.values) {
      final weapon = raw as Map<String, dynamic>;
      final name = weapon['name'] as String?;
      if (name == null || name.isEmpty) continue;

      weapons.add(
        MasterWeapon(
          id: '${weapon['id']}',
          name: name,
          weaponType:
              weaponTypeMap[weapon['type'] as String? ?? ''] ?? 'sword',
          rarity: (weapon['rank'] as num?)?.toInt() ?? 3,
          iconUrl: buildIconUrl(weapon['icon'] as String? ?? ''),
        ),
      );
    }

    weapons.sort((a, b) => a.name.compareTo(b.name));
    return weapons;
  }

  Future<List<MasterMaterial>> fetchMaterials() async {
    final items = await _fetchItems('/material');
    final materials = <MasterMaterial>[];

    for (final raw in items.values) {
      final material = raw as Map<String, dynamic>;
      final name = material['name'] as String?;
      final type = material['type'] as String? ?? '';
      if (name == null || name.isEmpty || !materialCategories.contains(type)) {
        continue;
      }

      materials.add(
        MasterMaterial(
          id: '${material['id']}',
          name: name,
          category: type,
          rarity: (material['rank'] as num?)?.toInt(),
          iconUrl: buildIconUrl(material['icon'] as String? ?? ''),
        ),
      );
    }

    materials.sort((a, b) => a.name.compareTo(b.name));
    return materials;
  }

  Future<Map<String, dynamic>> fetchAvatarDetail(String id) async {
    return _fetchDetail('/avatar/$id');
  }

  Future<Map<String, dynamic>> fetchWeaponDetail(String id) async {
    return _fetchDetail('/weapon/$id');
  }

  void dispose() => _client.close();
}
