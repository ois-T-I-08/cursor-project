import '../../config/feature_flags.dart';
import '../hoyolab/hoyolab_api.dart';
import '../hoyolab/hoyolab_constants.dart';
import '../hoyolab/hoyolab_cookie_service.dart';
import '../hoyolab/hoyolab_exceptions.dart';
import '../hoyolab/models/daily_note.dart';
import '../secure/secure_storage_service.dart';

class HoyolabRepository {
  HoyolabRepository({
    required SecureStorageService secureStorage,
    required FeatureFlags featureFlags,
    HoyolabCookieService? cookieService,
    HoyolabApi Function({
      required String cookie,
      String? region,
      String? uid,
      String appVersion,
    })? apiFactory,
  })  : _secure = secureStorage,
        _flags = featureFlags,
        _cookieService = cookieService ?? const HoyolabCookieService(),
        _apiFactory = apiFactory ??
            (({
              required cookie,
              region,
              uid,
              required appVersion,
            }) =>
                HoyolabApi(
                  cookie: cookie,
                  region: region,
                  uid: uid,
                  appVersion: appVersion,
                ));

  final SecureStorageService _secure;
  final FeatureFlags _flags;
  final HoyolabCookieService _cookieService;
  final HoyolabApi Function({
    required String cookie,
    String? region,
    String? uid,
    required String appVersion,
  }) _apiFactory;

  void _ensureEnabled() {
    if (!_flags.hoyolabLinkEnabled) {
      throw StateError('HoYoLAB link is disabled by feature flag');
    }
  }

  Future<String> _resolveAppVersion() async {
    final override = await _secure.getAppVersionOverride();
    return override ?? HoyolabConstants.defaultAppVersion;
  }

  Future<HoyolabApi> _apiFromStorage() async {
    final cookie = await _secure.getCookie();
    if (cookie == null || cookie.isEmpty) {
      throw StateError('Not linked');
    }
    return _apiFactory(
      cookie: cookie,
      region: await _secure.getRegion(),
      uid: await _secure.getUid(),
      appVersion: await _resolveAppVersion(),
    );
  }

  Future<HoyolabSession> loadSession() async {
    if (!_flags.hoyolabLinkEnabled) {
      return HoyolabSession.unlinked;
    }
    final cookie = await _secure.getCookie();
    if (cookie == null || cookie.isEmpty) {
      return HoyolabSession.unlinked;
    }
    return HoyolabSession(
      isLinked: true,
      uid: await _secure.getUid(),
      region: await _secure.getRegion(),
      nickname: await _secure.getNickname(),
    );
  }

  Future<String?> fetchCookieFromWebView() => _cookieService.fetchCookieString();

  Future<HoyolabSession> completeLogin({required String cookie}) async {
    _ensureEnabled();
    await _secure.saveCookie(cookie);
    final api = _apiFactory(
      cookie: cookie,
      appVersion: await _resolveAppVersion(),
    );
    final user = await api.verifyLToken();

    final roles = await _fetchAllRoles(api);
    if (roles.isEmpty) {
      throw const HoyolabApiException(-1, '原神のゲームアカウントが見つかりません');
    }

    final existingUid = await _secure.getUid();
    final selected = existingUid == null
        ? roles.first
        : roles.firstWhere(
            (r) => r.uid == existingUid,
            orElse: () => roles.first,
          );

    await _secure.saveRole(
      uid: selected.uid,
      region: selected.region,
      nickname: selected.nickname,
    );

    return HoyolabSession(
      isLinked: true,
      uid: selected.uid,
      region: selected.region,
      nickname: selected.nickname,
      accountName: user.accountName,
    );
  }

  Future<List<HoyolabGameRole>> fetchAvailableRoles() async {
    _ensureEnabled();
    final api = await _apiFromStorage();
    return _fetchAllRoles(api);
  }

  Future<List<HoyolabGameRole>> _fetchAllRoles(HoyolabApi api) async {
    final regions = await api.lookupRegions();
    final targetRegions = regions.isEmpty
        ? [const HoyolabRegion(region: 'os_asia', name: 'Asia')]
        : regions;

    final allRoles = <HoyolabGameRole>[];
    for (final region in targetRegions) {
      try {
        final roles = await api.getUserGameRoles(region: region.region);
        allRoles.addAll(roles);
      } on HoyolabApiException {
        // 空リージョンはスキップ
      }
    }
    return allRoles;
  }

  Future<HoyolabSession> selectRole(HoyolabGameRole role) async {
    _ensureEnabled();
    await _secure.saveRole(
      uid: role.uid,
      region: role.region,
      nickname: role.nickname,
    );
    final session = await loadSession();
    return session.copyWith(
      uid: role.uid,
      region: role.region,
      nickname: role.nickname,
    );
  }

  Future<DailyNote> fetchDailyNote() async {
    _ensureEnabled();
    final api = await _apiFromStorage();
    return api.getDailyNote();
  }

  Future<HoyolabApi?> tryApi() async {
    if (!_flags.hoyolabLinkEnabled) return null;
    final cookie = await _secure.getCookie();
    if (cookie == null || cookie.isEmpty) return null;
    final uid = await _secure.getUid();
    final region = await _secure.getRegion();
    if (uid == null || uid.isEmpty || region == null || region.isEmpty) {
      return null;
    }
    return _apiFactory(
      cookie: cookie,
      region: region,
      uid: uid,
      appVersion: await _resolveAppVersion(),
    );
  }

  Future<void> disconnect() async {
    await _secure.deleteHoyolabSession();
  }
}
