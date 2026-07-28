import '../config/config_load_log.dart';
import 'artifact_score_weight.dart';
import 'artifact_score_weight_source.dart';

const _configKind = 'artifact_score_weights';

class CompositeArtifactScoreWeightSource
    implements RefreshableArtifactScoreWeightSource {
  CompositeArtifactScoreWeightSource({
    required ArtifactScoreWeightSource localSource,
    RefreshableArtifactScoreWeightSource? remoteSource,
    this.refreshInterval = const Duration(hours: 12),
  }) : _localSource = localSource,
       _remoteSource = remoteSource;

  final ArtifactScoreWeightSource _localSource;
  final RefreshableArtifactScoreWeightSource? _remoteSource;
  final Duration refreshInterval;

  List<ArtifactScoreWeightProfile>? _cache;
  DateTime? _lastRefreshAt;

  @override
  Future<List<ArtifactScoreWeightProfile>> loadProfiles() async {
    if (_cache == null) {
      _cache = await _buildMergedProfiles();
      _lastRefreshAt = DateTime.now();
      return _cache!;
    }
    if (_shouldRefresh()) {
      try {
        _cache = await _buildMergedProfiles();
        _lastRefreshAt = DateTime.now();
      } catch (_) {
        // リモート更新失敗時は既存キャッシュを利用（invalid remote で破壊しない）
      }
    }
    return _cache!;
  }

  @override
  Future<List<ArtifactScoreWeightProfile>> refreshProfiles() async {
    _cache = await _buildMergedProfiles(forceRemote: true);
    _lastRefreshAt = DateTime.now();
    return _cache!;
  }

  bool _shouldRefresh() {
    final last = _lastRefreshAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= refreshInterval;
  }

  Future<List<ArtifactScoreWeightProfile>> _buildMergedProfiles({
    bool forceRemote = false,
  }) async {
    late final List<ArtifactScoreWeightProfile> local;
    try {
      local = await _localSource.loadProfiles();
    } catch (e) {
      logLocalConfigFailed(kind: _configKind, error: e);
      rethrow;
    }
    final byId = {for (final p in local) p.characterId: p};

    final remote = _remoteSource;
    if (remote != null) {
      try {
        final remoteProfiles =
            forceRemote
                ? await remote.refreshProfiles()
                : await remote.loadProfiles();
        for (final p in remoteProfiles) {
          byId[p.characterId] = p;
        }
      } catch (e) {
        logRemoteFallback(kind: _configKind, error: e);
      }
    }
    return byId.values.toList(growable: false);
  }
}
