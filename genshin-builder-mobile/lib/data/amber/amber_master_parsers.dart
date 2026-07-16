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
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid character record');
    }
    final avatar = raw;
    // element が null のデータ（未実装のドール等）は除外（Web project-amber と同方針）
    final elementKey = avatar['element'];
    if (elementKey != null && elementKey is! String) {
      throw const FormatException('Invalid character record');
    }
    final element =
        elementKey is String ? elementMap[elementKey] : null;
    final name = avatar['name'] as String?;
    final rank = (avatar['rank'] as num?)?.toInt();
    if (name == null || name.isEmpty || (rank != 4 && rank != 5)) {
      throw const FormatException('Invalid character record');
    }
    if (element == null) continue;

    final id = '${avatar['id']}';
    if (id.isEmpty || id == 'null') {
      throw const FormatException('Invalid character id');
    }
    if (id.startsWith('10000007-')) continue;

    final isTraveler = id.startsWith('10000005-');
    final displayName =
        isTraveler ? '旅人（${elementLabelMap[element] ?? element}）' : name;

    characters.add(
      MasterCharacter(
        id: id,
        name: displayName,
        element: element,
        weaponType:
            weaponTypeMap[avatar['weaponType'] as String? ?? ''] ?? 'sword',
        rarity: rank!,
        region: normalizeCharacterRegionForDisplay(
          regionMap[avatar['region'] as String? ?? ''] ??
              avatar['region'] as String? ??
              '',
          characterId: id,
          characterName: displayName,
        ),
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

/// 同期対象キャラ件数（旅人女スキップ・null element 除外 — parse と同じ条件）
int countSyncableCharactersFromAmberItems(Map<String, dynamic> items) {
  var count = 0;
  for (final raw in items.values) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid character record');
    }
    final avatar = raw;
    final elementKey = avatar['element'];
    if (elementKey != null && elementKey is! String) {
      throw const FormatException('Invalid character record');
    }
    final element =
        elementKey is String ? elementMap[elementKey] : null;
    final name = avatar['name'] as String?;
    final rank = (avatar['rank'] as num?)?.toInt();
    if (name == null || name.isEmpty || (rank != 4 && rank != 5)) {
      throw const FormatException('Invalid character record');
    }
    if (element == null) continue;
    final id = '${avatar['id']}';
    if (id.isEmpty || id == 'null') {
      throw const FormatException('Invalid character id');
    }
    if (id.startsWith('10000007-')) continue;
    count++;
  }
  return count;
}

List<MasterWeapon> parseWeaponsFromAmberItems(Map<String, dynamic> items) {
  final weapons = <MasterWeapon>[];
  for (final raw in items.values) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid weapon record');
    }
    final weapon = raw;
    final name = weapon['name'] as String?;
    final id = '${weapon['id']}';
    final rank = (weapon['rank'] as num?)?.toInt();
    if (name == null ||
        name.isEmpty ||
        id.isEmpty ||
        id == 'null' ||
        rank == null ||
        rank < 1 ||
        rank > 5) {
      throw const FormatException('Invalid weapon record');
    }
    weapons.add(
      MasterWeapon(
        id: id,
        name: name,
        weaponType: weaponTypeMap[weapon['type'] as String? ?? ''] ?? 'sword',
        rarity: rank,
        iconUrl: buildIconUrl(weapon['icon'] as String? ?? ''),
      ),
    );
  }
  return weapons;
}

List<MasterMaterial> parseMaterialsFromAmberItems(Map<String, dynamic> items) {
  final materials = <MasterMaterial>[];
  for (final entry in items.entries) {
    if (entry.value is! Map<String, dynamic>) {
      throw const FormatException('Invalid material record');
    }
    final material = entry.value as Map<String, dynamic>;
    final name = material['name'] as String?;
    final rank = (material['rank'] as num?)?.toInt();
    if (entry.key.isEmpty ||
        name == null ||
        name.isEmpty ||
        (rank != null && (rank < 1 || rank > 5))) {
      throw const FormatException('Invalid material record');
    }
    materials.add(
      MasterMaterial(
        id: entry.key,
        name: name,
        category: material['type'] as String? ?? '',
        rarity: rank,
        iconUrl: buildIconUrl(material['icon'] as String? ?? ''),
      ),
    );
  }
  return materials;
}

/// Isolate.run 用ペイロード（characters）
List<MasterCharacter> parseCharactersIsolatePayload(
  Map<String, dynamic> payload,
) {
  final items = Map<String, dynamic>.from(payload['items'] as Map);
  final overrides = <String, String>{
    for (final e in (payload['nameOverrides'] as Map? ?? const {}).entries)
      e.key as String: e.value as String,
  };
  return parseCharactersFromAmberItems(items, nameOverrideStorage: overrides);
}
