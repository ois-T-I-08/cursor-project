import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'hoyolab_game_providers.dart';
import 'hoyolab_home_providers.dart';

/// HoYoLAB ゲーム記録の手動更新（キャッシュを破棄してから再取得）
void refreshHoyolabOwnedCharacters(WidgetRef ref) {
  ref.read(hoyolabGameDataCacheProvider).clearOwned();
  ref.invalidate(hoyolabOwnedFetchResultProvider);
  ref.invalidate(hoyolabOwnedCharacterMapProvider);
  ref.invalidate(sortedCharacterEntriesProvider);
}

void refreshHoyolabCharacterBuild(WidgetRef ref, String characterId) {
  ref.read(hoyolabGameDataCacheProvider).clearCharacterBuild(characterId);
  ref.invalidate(hoyolabCharacterBuildProvider(characterId));
}

void refreshHoyolabAdventureStatus(WidgetRef ref) {
  ref.read(hoyolabGameDataCacheProvider).clearAdventure();
  ref.read(hoyolabAdventureStatusProvider.notifier).refresh();
}

void refreshAllHoyolabGameData(WidgetRef ref) {
  ref.read(hoyolabGameDataCacheProvider).clear();
  refreshHoyolabOwnedCharacters(ref);
  ref.read(hoyolabAdventureStatusProvider.notifier).refresh();
}

String formatRelativeUpdateTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'たった今';
  if (diff.inHours < 1) return '${diff.inMinutes}分前';
  if (diff.inHours < 24) return '${diff.inHours}時間前';
  return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
}
