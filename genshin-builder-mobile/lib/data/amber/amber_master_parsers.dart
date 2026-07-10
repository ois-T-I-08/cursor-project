import '../../domain/artifact_score.dart';
import '../../domain/models/master_models.dart';
import 'amber_constants.dart';

/// Amber 一覧 JSON → マスタへの変換（Isolate で実行可能な純関数）
List<MasterCharacter> parseCharactersFromAmberItems(
  Map<String, dynamic> items, {
  Map<String, String> nameOverrideStorage = const {},
}) {
  final nameOverrides = <String, ArtifactScoreType>{
    for (final e in nameOverrideStorage.entries)
      if (artifactScoreTypeFromString(e.value) != null)
        e.key: artifactScoreTypeFromString(e.value)!,
  };

  final characters = <MasterCharacter>[];
  for (final raw in items.values) {
    final avatar = raw as Map<String, dynamic>;
    final elementKey = avatar['element'] as String?;
    final element = elementKey != null ? elementMap[elementKey] : null;
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
        scoreType: artifactScoreTypeToStorage(
          inferScoreType(
            avatar['specialProp'] as String?,
            name,
            nameOverrides: nameOverrides,
          ),
        ),
      ),
    );
  }
  return characters;
}

List<MasterWeapon> parseWeaponsFromAmberItems(Map<String, dynamic> items) {
  final weapons = <MasterWeapon>[];
  for (final raw in items.values) {
    final weapon = raw as Map<String, dynamic>;
    final name = weapon['name'] as String?;
    if (name == null || name.isEmpty) continue;
    weapons.add(
      MasterWeapon(
        id: '${weapon['id']}',
        name: name,
        weaponType: weaponTypeMap[weapon['type'] as String? ?? ''] ?? 'sword',
        rarity: (weapon['rank'] as num?)?.toInt() ?? 1,
        iconUrl: buildIconUrl(weapon['icon'] as String? ?? ''),
      ),
    );
  }
  return weapons;
}

List<MasterMaterial> parseMaterialsFromAmberItems(Map<String, dynamic> items) {
  final materials = <MasterMaterial>[];
  for (final entry in items.entries) {
    final material = entry.value as Map<String, dynamic>;
    final name = material['name'] as String?;
    if (name == null || name.isEmpty) continue;
    materials.add(
      MasterMaterial(
        id: entry.key,
        name: name,
        category: material['type'] as String? ?? '',
        rarity: (material['rank'] as num?)?.toInt(),
        iconUrl: buildIconUrl(material['icon'] as String? ?? ''),
      ),
    );
  }
  return materials;
}

/// Isolate.run 用ペイロード（characters）
List<MasterCharacter> parseCharactersIsolatePayload(Map<String, dynamic> payload) {
  final items = Map<String, dynamic>.from(payload['items'] as Map);
  final overrides = <String, String>{
    for (final e in (payload['nameOverrides'] as Map? ?? const {}).entries)
      e.key as String: e.value as String,
  };
  return parseCharactersFromAmberItems(items, nameOverrideStorage: overrides);
}
