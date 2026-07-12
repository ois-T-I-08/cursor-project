import '../../domain/gacha/gacha_banner.dart';
import '../../domain/gacha/gacha_banner_schedule.dart';
import 'asset_gacha_banner_history_source.dart';
import 'gacha_calendar_api.dart';

class GachaBannerLoadResult {
  const GachaBannerLoadResult({
    required this.banners,
    this.liveError,
  });

  final List<GachaBanner> banners;
  final Object? liveError;

  bool get hasLiveError => liveError != null;
}

/// 履歴（asset/remote）＋現行カレンダーをマージしてソートする。
class GachaBannerRepository {
  GachaBannerRepository({
    required GachaBannerHistorySource historySource,
    GachaCalendarApi? calendarApi,
  })  : _historySource = historySource,
        _calendarApi = calendarApi ?? GachaCalendarApi();

  final GachaBannerHistorySource _historySource;
  final GachaCalendarApi _calendarApi;

  Future<GachaBannerLoadResult> loadBanners({DateTime? now}) async {
    final schedule = await _historySource.load();
    Object? liveError;
    var live = <GachaBanner>[];
    try {
      live = await _calendarApi.fetchCurrentBanners();
    } catch (e) {
      liveError = e;
    }

    final merged = mergeGachaBanners(
      history: schedule.banners,
      live: live,
    );
    return GachaBannerLoadResult(
      banners: sortGachaBanners(merged, now: now),
      liveError: liveError,
    );
  }
}

/// リモートがあれば優先、失敗時はアセットへフォールバック。
class PreferRemoteGachaBannerHistorySource implements GachaBannerHistorySource {
  PreferRemoteGachaBannerHistorySource({
    required this.remote,
    required this.fallback,
  });

  final GachaBannerHistorySource remote;
  final GachaBannerHistorySource fallback;

  @override
  Future<GachaBannerSchedule> load() async {
    try {
      return await remote.load();
    } catch (_) {
      return fallback.load();
    }
  }
}
