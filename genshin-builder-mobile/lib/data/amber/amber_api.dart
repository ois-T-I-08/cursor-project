import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import '../artifact_score/artifact_score_type_override_registry.dart';
import '../models/master_models.dart';
import '../../domain/artifact_score.dart';
import 'amber_constants.dart';
import 'amber_master_parsers.dart';

/// 大きな JSON は isolate でデコードし、メイン isolate のブロックを避ける
const _isolateJsonThresholdBytes = 32 * 1024;

Future<Map<String, dynamic>> decodeJsonMap(String body) async {
  if (body.length < _isolateJsonThresholdBytes) {
    return jsonDecode(body) as Map<String, dynamic>;
  }
  return Isolate.run(() => jsonDecode(body) as Map<String, dynamic>);
}

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
    final json = await decodeJsonMap(response.body);
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
    final json = await decodeJsonMap(response.body);
    if (json['response'] != 200) {
      throw Exception('Amber API response error: $path');
    }
    return json['data'] as Map<String, dynamic>;
  }

  /// 言語非依存の static データ（成長曲線など）を取得する。
  /// 例: `/avatarCurve`, `/weaponCurve`
  Future<Map<String, dynamic>> fetchStaticData(String path) async {
    final uri = Uri.parse('$amberBaseUrl/api/v2/static$path');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Amber API error: ${response.statusCode} static$path');
    }
    final json = await decodeJsonMap(response.body);
    if (json['response'] != 200) {
      throw Exception('Amber API response error: static$path');
    }
    return json['data'] as Map<String, dynamic>;
  }

  Future<List<MasterCharacter>> fetchCharacters() async {
    final overrideRegistry = ArtifactScoreTypeOverrideRegistry.instance;
    await overrideRegistry.ensureLoaded();
    final nameOverrides = overrideRegistry.byName;

    final items = await _fetchItems('/avatar');
    final payload = <String, dynamic>{
      'items': items,
      'nameOverrides': {
        for (final e in nameOverrides.entries)
          e.key: artifactScoreTypeToStorage(e.value),
      },
    };
    return Isolate.run(() => parseCharactersIsolatePayload(payload));
  }

  Future<List<MasterWeapon>> fetchWeapons() async {
    final items = await _fetchItems('/weapon');
    return Isolate.run(() => parseWeaponsFromAmberItems(items));
  }

  Future<List<MasterMaterial>> fetchMaterials() async {
    final items = await _fetchItems('/material');
    return Isolate.run(() => parseMaterialsFromAmberItems(items));
  }

  /// 一覧件数のみ（プローブ用。突破詳細は取得しない）。3 エンドポイント並列。
  Future<({int characters, int weapons, int materials})>
      fetchMasterListCounts() async {
    final results = await Future.wait([
      _fetchItems('/avatar'),
      _fetchItems('/weapon'),
      _fetchItems('/material'),
    ]);
    final avatars = results[0];
    final weapons = results[1];
    final materials = results[2];
    return (
      characters: countSyncableCharactersFromAmberItems(avatars),
      weapons: weapons.length,
      materials: materials.length,
    );
  }

  Future<Map<String, dynamic>> fetchAvatarDetail(String id) =>
      _fetchDetail('/avatar/$id');

  Future<Map<String, dynamic>> fetchWeaponDetail(String id) =>
      _fetchDetail('/weapon/$id');

  Future<Map<String, dynamic>> fetchReliquaryItems() async {
    return _fetchItems('/reliquary');
  }

  void close() => _client.close();

  void dispose() => close();
}
