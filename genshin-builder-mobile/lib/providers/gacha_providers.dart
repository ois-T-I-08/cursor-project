import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/gacha/asset_gacha_banner_history_source.dart';
import '../data/gacha/gacha_banner_repository.dart';
import '../data/gacha/gacha_calendar_api.dart';
import '../data/gacha/remote_gacha_banner_history_source.dart';
import '../domain/gacha/calendar_event.dart';
import '../domain/gacha/gacha_banner.dart';
import '../domain/models/master_models.dart';
import 'app_providers.dart';

final gachaBannerHistorySourceProvider =
    Provider<GachaBannerHistorySource>((ref) {
  const remoteUrl = String.fromEnvironment(
    'GACHA_BANNER_HISTORY_URL',
    defaultValue: '',
  );
  final asset = AssetGachaBannerHistorySource();
  if (remoteUrl.isEmpty) return asset;
  return PreferRemoteGachaBannerHistorySource(
    remote: RemoteGachaBannerHistorySource(url: remoteUrl),
    fallback: asset,
  );
});

final gachaCalendarApiProvider = Provider<GachaCalendarApi>((ref) {
  final api = GachaCalendarApi();
  ref.onDispose(api.dispose);
  return api;
});

final gachaBannerRepositoryProvider = Provider<GachaBannerRepository>((ref) {
  return GachaBannerRepository(
    historySource: ref.watch(gachaBannerHistorySourceProvider),
    calendarApi: ref.watch(gachaCalendarApiProvider),
  );
});

final gachaBannersProvider =
    FutureProvider<GachaBannerLoadResult>((ref) async {
  final repo = ref.watch(gachaBannerRepositoryProvider);
  return repo.loadBanners();
});

/// ホーム用: 開催中＋予告イベント（期間不明は除外）
final homeCalendarEventsProvider =
    FutureProvider<List<CalendarEvent>>((ref) async {
  final api = ref.watch(gachaCalendarApiProvider);
  final events = await api.fetchCurrentEvents();
  return sortCalendarEventsForHome(events);
});

final weaponsProvider = FutureProvider<List<MasterWeapon>>((ref) async {
  final repo = await ref.watch(characterRepositoryProvider.future);
  return repo.getAllWeapons();
});

/// 表示用に解決済みの featured アイコン情報
class GachaFeaturedIcon {
  const GachaFeaturedIcon({
    required this.id,
    required this.label,
    this.iconUrl,
    this.characterId,
  });

  final String id;
  final String label;
  final String? iconUrl;

  /// キャラ詳細へ遷移可能ならセット
  final String? characterId;
}

List<GachaFeaturedIcon> resolveGachaFeaturedIcons({
  required GachaBanner banner,
  required Map<String, MasterCharacter> charactersById,
  required Map<String, MasterWeapon> weaponsById,
}) {
  final out = <GachaFeaturedIcon>[];

  void addCharacter(String id) {
    final c = charactersById[id];
    out.add(
      GachaFeaturedIcon(
        id: id,
        label: c?.name ?? id,
        iconUrl: c?.iconUrl ?? banner.sourceIcons[id],
        characterId: c?.id,
      ),
    );
  }

  void addWeapon(String id) {
    final w = weaponsById[id];
    out.add(
      GachaFeaturedIcon(
        id: id,
        label: w?.name ?? id,
        iconUrl: w?.iconUrl ?? banner.sourceIcons[id],
      ),
    );
  }

  for (final id in banner.featured5Ids) {
    addCharacter(id);
  }
  for (final id in banner.featured4Ids) {
    addCharacter(id);
  }
  for (final id in banner.featuredWeaponIds) {
    addWeapon(id);
  }
  return out;
}
