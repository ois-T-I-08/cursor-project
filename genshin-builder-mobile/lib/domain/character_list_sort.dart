import '../data/models/master_models.dart';
import '../data/hoyolab/models/game_record.dart';
import '../data/hoyolab/owned_characters_result.dart';

class CharacterListEntry {
  const CharacterListEntry({
    required this.character,
    required this.isOwned,
    this.owned,
  });

  final MasterCharacter character;
  final bool isOwned;
  final HoyolabOwnedCharacter? owned;
}

List<CharacterListEntry> buildCharacterListEntries({
  required List<MasterCharacter> characters,
  required Map<String, HoyolabOwnedCharacter> ownedMap,
}) {
  final owned = <CharacterListEntry>[];
  final unowned = <CharacterListEntry>[];

  for (final character in characters) {
    final ownedInfo = lookupOwnedCharacter(ownedMap, character.id);
    final entry = CharacterListEntry(
      character: character,
      isOwned: ownedInfo != null,
      owned: ownedInfo,
    );
    if (ownedInfo != null) {
      owned.add(entry);
    } else {
      unowned.add(entry);
    }
  }

  owned.sort(_compareOwnedEntries);
  unowned.sort(
    (a, b) => a.character.name.compareTo(b.character.name),
  );

  return [...owned, ...unowned];
}

int _compareOwnedEntries(CharacterListEntry a, CharacterListEntry b) {
  final oa = a.owned!;
  final ob = b.owned!;

  final aDate = oa.obtainedAt;
  final bDate = ob.obtainedAt;
  if (aDate != null && bDate != null) {
    final cmp = bDate.compareTo(aDate);
    if (cmp != 0) return cmp;
  }

  final levelCmp = ob.level.compareTo(oa.level);
  if (levelCmp != 0) return levelCmp;

  return a.character.name.compareTo(b.character.name);
}
