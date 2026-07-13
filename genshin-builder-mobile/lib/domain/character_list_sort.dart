import 'game_display.dart';
import 'models/master_models.dart';

export 'game_display.dart' show gameRegionDisplayOrder, gameRegionSortIndex;

/// 一覧ソート用の所持キャラ情報（HoYoLAB DTO に依存しない）
class OwnedCharacterSortInfo {
  const OwnedCharacterSortInfo({
    required this.level,
    this.friendship = 0,
    this.constellation = 0,
    this.obtainedAt,
  });

  final int level;
  final int friendship;
  final int constellation;
  final DateTime? obtainedAt;
}

/// キャラクター一覧の並び替えモード
enum CharacterListSortMode {
  region,
  ownedDefault,
  nameAsc,
  nameDesc,
  rarityDesc,
  rarityAsc,
  element,
  levelDesc,
  levelAsc,
  obtainedDesc,
  obtainedAsc,
  constellationDesc,
  friendshipDesc,
}

extension CharacterListSortModeLabels on CharacterListSortMode {
  String get label => switch (this) {
        CharacterListSortMode.region => '地域（聖遺物と同じ順）',
        CharacterListSortMode.ownedDefault => '所持優先（取得推定順）',
        CharacterListSortMode.nameAsc => '名前（あ→ん）',
        CharacterListSortMode.nameDesc => '名前（ん→あ）',
        CharacterListSortMode.rarityDesc => 'レアリティ（高い順）',
        CharacterListSortMode.rarityAsc => 'レアリティ（低い順）',
        CharacterListSortMode.element => '元素',
        CharacterListSortMode.levelDesc => 'レベル（高い順）',
        CharacterListSortMode.levelAsc => 'レベル（低い順）',
        CharacterListSortMode.obtainedDesc => '取得推定（新しい順）',
        CharacterListSortMode.obtainedAsc => '取得推定（古い順）',
        CharacterListSortMode.constellationDesc => '命ノ星座（多い順）',
        CharacterListSortMode.friendshipDesc => '好感度（高い順）',
      };

  static CharacterListSortMode fromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return CharacterListSortMode.region;
    return CharacterListSortMode.values.firstWhere(
      (mode) => mode.name == raw,
      orElse: () => CharacterListSortMode.region,
    );
  }
}

class CharacterListSortSettings {
  const CharacterListSortSettings({
    this.mode = CharacterListSortMode.region,
    this.groupByOwnership = false,
  });

  final CharacterListSortMode mode;
  final bool groupByOwnership;

  static const storageKeyMode = 'character_list_sort_mode';
  static const storageKeyGroup = 'character_list_group_by_ownership';
  /// 聖遺物と同じ地域順への移行済みフラグ（未移行端末は一度だけ region へ切替）
  static const storageKeyRegionDefaultMigration =
      'character_list_sort_region_default_v1';

  CharacterListSortSettings copyWith({
    CharacterListSortMode? mode,
    bool? groupByOwnership,
  }) =>
      CharacterListSortSettings(
        mode: mode ?? this.mode,
        groupByOwnership: groupByOwnership ?? this.groupByOwnership,
      );
}

class CharacterListEntry {
  const CharacterListEntry({
    required this.character,
    required this.isOwned,
    this.owned,
  });

  final MasterCharacter character;
  final bool isOwned;
  final OwnedCharacterSortInfo? owned;
}

/// 地域セクション（聖遺物一覧と同じ並び）
class CharacterRegionSection {
  const CharacterRegionSection({
    required this.region,
    required this.items,
  });

  final String region;
  final List<CharacterListEntry> items;
}

/// マスター ID と所持マップの照合（旅人の元素 suffix 対応）
OwnedCharacterSortInfo? lookupOwnedSortInfo(
  Map<String, OwnedCharacterSortInfo> ownedMap,
  String masterCharacterId,
) {
  final direct = ownedMap[masterCharacterId];
  if (direct != null) return direct;
  final baseId = masterCharacterId.split('-').first;
  return ownedMap[baseId];
}

const _elementOrder = [
  'pyro',
  'hydro',
  'anemo',
  'electro',
  'dendro',
  'cryo',
  'geo',
];

List<CharacterListEntry> buildCharacterListEntries({
  required List<MasterCharacter> characters,
  required Map<String, OwnedCharacterSortInfo> ownedMap,
  CharacterListSortSettings settings = const CharacterListSortSettings(),
}) {
  final entries = characters
      .map((character) {
        final ownedInfo = lookupOwnedSortInfo(ownedMap, character.id);
        return CharacterListEntry(
          character: character,
          isOwned: ownedInfo != null,
          owned: ownedInfo,
        );
      })
      .toList(growable: false);

  // 地域モードは所持グループより地域セクションを優先（聖遺物一覧と同じ）
  if (settings.mode == CharacterListSortMode.region) {
    final sorted = [...entries]
      ..sort((a, b) => _compareEntries(a, b, CharacterListSortMode.region));
    return sorted;
  }

  if (settings.groupByOwnership &&
      settings.mode == CharacterListSortMode.ownedDefault) {
    return _buildOwnedDefaultSplit(entries);
  }

  if (settings.groupByOwnership) {
    final owned = entries.where((entry) => entry.isOwned).toList();
    final unowned = entries.where((entry) => !entry.isOwned).toList();
    owned.sort((a, b) => _compareEntries(a, b, settings.mode));
    unowned.sort((a, b) => _compareEntries(a, b, settings.mode));
    return [...owned, ...unowned];
  }

  final sorted = [...entries]
    ..sort((a, b) => _compareEntries(a, b, settings.mode));
  return sorted;
}

/// 聖遺物一覧と同じ地域順でセクション化。
List<CharacterRegionSection> groupCharacterEntriesByRegion(
  List<CharacterListEntry> entries, {
  List<String> regionOrder = gameRegionDisplayOrder,
}) {
  final byRegion = <String, List<CharacterListEntry>>{};
  final travelerEntries = <CharacterListEntry>[];
  for (final e in entries) {
    // 旅人（ID 10000005-* / 10000007-*）は専用セクションへ
    final baseId = e.character.id.split('-').first;
    if (baseId == '10000005' || baseId == '10000007') {
      travelerEntries.add(e);
      continue;
    }
    final region = normalizeCharacterRegionForDisplay(
      e.character.region,
      characterId: e.character.id,
      characterName: e.character.name,
    );
    byRegion.putIfAbsent(region, () => []).add(e);
  }
  for (final list in byRegion.values) {
    list.sort((a, b) {
      final byRarity = b.character.rarity.compareTo(a.character.rarity);
      if (byRarity != 0) return byRarity;
      return a.character.name.compareTo(b.character.name);
    });
  }

  final sections = <CharacterRegionSection>[];
  // 旅人セクションを先頭（モンドの直前）に追加
  if (travelerEntries.isNotEmpty) {
    sections.add(CharacterRegionSection(
      region: '旅人',
      items: travelerEntries,
    ));
  }
  final seen = <String>{};
  for (final region in regionOrder) {
    final items = byRegion[region];
    if (items == null || items.isEmpty) continue;
    sections.add(CharacterRegionSection(region: region, items: items));
    seen.add(region);
  }
  final extras = byRegion.keys.where((k) => !seen.contains(k)).toList()
    ..sort();
  for (final region in extras) {
    final items = byRegion[region];
    if (items == null || items.isEmpty) continue;
    sections.add(CharacterRegionSection(region: region, items: items));
  }
  return sections;
}

List<CharacterListEntry> _buildOwnedDefaultSplit(
  List<CharacterListEntry> entries,
) {
  final owned = entries.where((entry) => entry.isOwned).toList()
    ..sort(_compareOwnedDefault);
  final unowned = entries.where((entry) => !entry.isOwned).toList()
    ..sort((a, b) => a.character.name.compareTo(b.character.name));
  return [...owned, ...unowned];
}

int _compareEntries(
  CharacterListEntry a,
  CharacterListEntry b,
  CharacterListSortMode mode,
) {
  switch (mode) {
    case CharacterListSortMode.ownedDefault:
      return _compareOwnedDefault(a, b);
    case CharacterListSortMode.nameAsc:
      return a.character.name.compareTo(b.character.name);
    case CharacterListSortMode.nameDesc:
      return b.character.name.compareTo(a.character.name);
    case CharacterListSortMode.rarityDesc:
      return _compareIntDesc(a.character.rarity, b.character.rarity) != 0
          ? _compareIntDesc(a.character.rarity, b.character.rarity)
          : a.character.name.compareTo(b.character.name);
    case CharacterListSortMode.rarityAsc:
      return _compareIntAsc(a.character.rarity, b.character.rarity) != 0
          ? _compareIntAsc(a.character.rarity, b.character.rarity)
          : a.character.name.compareTo(b.character.name);
    case CharacterListSortMode.element:
      return _compareElement(a, b);
    case CharacterListSortMode.region:
      final regionCmp = gameRegionSortIndex(
        normalizeCharacterRegionForDisplay(
          a.character.region,
          characterId: a.character.id,
          characterName: a.character.name,
        ),
      ).compareTo(
        gameRegionSortIndex(
          normalizeCharacterRegionForDisplay(
            b.character.region,
            characterId: b.character.id,
            characterName: b.character.name,
          ),
        ),
      );
      if (regionCmp != 0) return regionCmp;
      final rarityCmp = b.character.rarity.compareTo(a.character.rarity);
      if (rarityCmp != 0) return rarityCmp;
      return a.character.name.compareTo(b.character.name);
    case CharacterListSortMode.levelDesc:
      return _compareOwnedIntDesc(
        a,
        b,
        (owned) => owned.level,
        tieBreaker: a.character.name.compareTo(b.character.name),
      );
    case CharacterListSortMode.levelAsc:
      return _compareOwnedIntAsc(
        a,
        b,
        (owned) => owned.level,
        tieBreaker: a.character.name.compareTo(b.character.name),
      );
    case CharacterListSortMode.obtainedDesc:
      return _compareObtained(a, b, descending: true);
    case CharacterListSortMode.obtainedAsc:
      return _compareObtained(a, b, descending: false);
    case CharacterListSortMode.constellationDesc:
      return _compareOwnedIntDesc(
        a,
        b,
        (owned) => owned.constellation,
        tieBreaker: a.character.name.compareTo(b.character.name),
      );
    case CharacterListSortMode.friendshipDesc:
      return _compareOwnedIntDesc(
        a,
        b,
        (owned) => owned.friendship,
        tieBreaker: a.character.name.compareTo(b.character.name),
      );
  }
}

int _compareElement(CharacterListEntry a, CharacterListEntry b) {
  final ai = _elementOrder.indexOf(a.character.element);
  final bi = _elementOrder.indexOf(b.character.element);
  final aOrder = ai < 0 ? 999 : ai;
  final bOrder = bi < 0 ? 999 : bi;
  final cmp = aOrder.compareTo(bOrder);
  return cmp != 0 ? cmp : a.character.name.compareTo(b.character.name);
}

int _compareObtained(
  CharacterListEntry a,
  CharacterListEntry b, {
  required bool descending,
}) {
  final ownedCmp = _compareOwnedFirst(a, b);
  if (ownedCmp != 0) return ownedCmp;
  final cmp = _compareObtainedDateAsc(a.owned?.obtainedAt, b.owned?.obtainedAt);
  if (cmp == 0) return a.character.name.compareTo(b.character.name);
  return descending ? -cmp : cmp;
}

int _compareObtainedDateAsc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

int _compareOwnedDefault(CharacterListEntry a, CharacterListEntry b) {
  final ownedCmp = _compareOwnedFirst(a, b);
  if (ownedCmp != 0) return ownedCmp;

  final dateCmp =
      _compareObtainedDateAsc(a.owned?.obtainedAt, b.owned?.obtainedAt);
  if (dateCmp != 0) return dateCmp;

  return a.character.name.compareTo(b.character.name);
}

int _compareOwnedFirst(CharacterListEntry a, CharacterListEntry b) {
  if (a.isOwned && !b.isOwned) return -1;
  if (!a.isOwned && b.isOwned) return 1;
  return 0;
}

int _compareOwnedIntDesc(
  CharacterListEntry a,
  CharacterListEntry b,
  int Function(OwnedCharacterSortInfo owned) selector, {
  required int tieBreaker,
}) {
  final ownedCmp = _compareOwnedFirst(a, b);
  if (ownedCmp != 0) return ownedCmp;

  final aValue = a.owned == null ? -1 : selector(a.owned!);
  final bValue = b.owned == null ? -1 : selector(b.owned!);
  final cmp = bValue.compareTo(aValue);
  return cmp != 0 ? cmp : tieBreaker;
}

int _compareOwnedIntAsc(
  CharacterListEntry a,
  CharacterListEntry b,
  int Function(OwnedCharacterSortInfo owned) selector, {
  required int tieBreaker,
}) {
  final ownedCmp = _compareOwnedFirst(a, b);
  if (ownedCmp != 0) return ownedCmp;

  final aValue = a.owned == null ? 999 : selector(a.owned!);
  final bValue = b.owned == null ? 999 : selector(b.owned!);
  final cmp = aValue.compareTo(bValue);
  return cmp != 0 ? cmp : tieBreaker;
}

int _compareIntDesc(int a, int b) => b.compareTo(a);

int _compareIntAsc(int a, int b) => a.compareTo(b);

/// セクション表示用: 所持/未所持の境界インデックス（groupByOwnership=true のとき）
int ownedEntryCount(List<CharacterListEntry> entries) =>
    entries.where((entry) => entry.isOwned).length;

bool shouldShowOwnershipSections(CharacterListSortSettings settings) {
  if (settings.mode == CharacterListSortMode.region) return false;
  if (!settings.groupByOwnership) return false;
  return true;
}

bool shouldShowRegionSections(CharacterListSortSettings settings) =>
    settings.mode == CharacterListSortMode.region;
