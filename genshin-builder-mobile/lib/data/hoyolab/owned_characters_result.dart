/// 所持キャラ取得結果（エラー可視化用）
library;

import 'hoyolab_exceptions.dart';
import 'models/game_record.dart';

class OwnedCharactersFetchResult {
  const OwnedCharactersFetchResult({
    required this.characters,
    this.error,
    this.notLinked = false,
    this.fetched = false,
  });

  final Map<String, HoyolabOwnedCharacter> characters;
  final HoyolabApiException? error;
  final bool notLinked;
  final bool fetched;

  bool get hasCharacters => characters.isNotEmpty;

  String? get userMessage {
    if (notLinked || !fetched) return null;
    if (error != null) return error!.userMessage;
    if (!hasCharacters) {
      return '所持キャラクターを取得できませんでした。ゲーム記録の公開設定を確認してください。';
    }
    return null;
  }
}

/// API のキャラ ID をマスター ID に照合（旅人の元素 suffix 対応）
HoyolabOwnedCharacter? lookupOwnedCharacter(
  Map<String, HoyolabOwnedCharacter> ownedMap,
  String masterCharacterId,
) {
  final direct = ownedMap[masterCharacterId];
  if (direct != null) return direct;

  final baseId = masterCharacterId.split('-').first;
  return ownedMap[baseId];
}

Map<String, HoyolabOwnedCharacter> indexOwnedCharacters(
  List<HoyolabOwnedCharacter> owned,
) {
  final map = <String, HoyolabOwnedCharacter>{};
  for (final character in owned) {
    map[character.id] = character;
  }
  return map;
}
