import 'akasha_weapon_usage.dart';
import 'akasha_weapon_usage_api.dart';

/// キャラ別武器使用率の取得・キャッシュ
class AkashaWeaponUsageRepository {
  AkashaWeaponUsageRepository({
    AkashaWeaponUsageApi? api,
    this.cacheTtl = const Duration(hours: 6),
    this.pages = 4,
    this.pageSize = 50,
  }) : _api = api ?? AkashaWeaponUsageApi();

  final AkashaWeaponUsageApi _api;
  final Duration cacheTtl;
  final int pages;
  final int pageSize;

  final Map<String, WeaponUsageSnapshot> _cache = {};
  final Map<String, Future<WeaponUsageSnapshot>> _inflight = {};

  /// 使用率を取得。失敗時は空の heuristic スナップショットを返す。
  Future<WeaponUsageSnapshot> getUsageRates(String characterId) {
    final cached = _cache[characterId];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < cacheTtl) {
      return Future.value(cached);
    }

    return _inflight.putIfAbsent(characterId, () async {
      try {
        final snap = await _api.fetchUsageRates(
          characterId: characterId,
          pages: pages,
          pageSize: pageSize,
        );
        if (snap.sampleSize > 0) {
          _cache[characterId] = snap;
          return snap;
        }
        return _heuristicEmpty(characterId);
      } catch (_) {
        return _heuristicEmpty(characterId);
      } finally {
        _inflight.remove(characterId);
      }
    });
  }

  WeaponUsageSnapshot _heuristicEmpty(String characterId) =>
      WeaponUsageSnapshot(
        characterId: characterId,
        rates: const {},
        sampleSize: 0,
        source: 'heuristic',
        fetchedAt: DateTime.now(),
      );

  void dispose() {
    _api.dispose();
    _cache.clear();
    _inflight.clear();
  }
}
