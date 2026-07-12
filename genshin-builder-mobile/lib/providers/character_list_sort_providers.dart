import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/character_list_sort.dart';
import 'app_providers.dart';

final characterListSortSettingsProvider =
    AsyncNotifierProvider<CharacterListSortSettingsNotifier,
        CharacterListSortSettings>(
  CharacterListSortSettingsNotifier.new,
);

class CharacterListSortSettingsNotifier
    extends AsyncNotifier<CharacterListSortSettings> {
  @override
  Future<CharacterListSortSettings> build() async {
    final db = await ref.watch(appDatabaseProvider.future);
    final migrated = await db.getSetting(
      CharacterListSortSettings.storageKeyRegionDefaultMigration,
    );

    // 旧既定（所持優先）が残っている端末向け: 一度だけ地域順へ移行
    if (migrated != '1') {
      const next = CharacterListSortSettings(
        mode: CharacterListSortMode.region,
        groupByOwnership: false,
      );
      await db.setSetting(
        CharacterListSortSettings.storageKeyMode,
        next.mode.name,
      );
      await db.setSetting(
        CharacterListSortSettings.storageKeyGroup,
        'false',
      );
      await db.setSetting(
        CharacterListSortSettings.storageKeyRegionDefaultMigration,
        '1',
      );
      return next;
    }

    final modeRaw = await db.getSetting(CharacterListSortSettings.storageKeyMode);
    final groupRaw =
        await db.getSetting(CharacterListSortSettings.storageKeyGroup);
    return CharacterListSortSettings(
      mode: CharacterListSortModeLabels.fromStorage(modeRaw),
      groupByOwnership: groupRaw == 'true',
    );
  }

  Future<void> updateSettings(CharacterListSortSettings settings) async {
    state = AsyncData(settings);
    final db = await ref.read(appDatabaseProvider.future);
    await db.setSetting(
      CharacterListSortSettings.storageKeyMode,
      settings.mode.name,
    );
    await db.setSetting(
      CharacterListSortSettings.storageKeyGroup,
      settings.groupByOwnership.toString(),
    );
    await db.setSetting(
      CharacterListSortSettings.storageKeyRegionDefaultMigration,
      '1',
    );
  }

  Future<void> setMode(CharacterListSortMode mode) async {
    final current = state.valueOrNull ?? const CharacterListSortSettings();
    await updateSettings(current.copyWith(mode: mode));
  }

  Future<void> setGroupByOwnership(bool value) async {
    final current = state.valueOrNull ?? const CharacterListSortSettings();
    await updateSettings(current.copyWith(groupByOwnership: value));
  }
}
