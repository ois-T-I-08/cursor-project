import '../../domain/artifact_score.dart';

typedef ArtifactScoreTypeOverrideLoader =
    Future<Map<String, ArtifactScoreType>> Function();

/// JSON 上書き定義の読み込みと参照。
class ArtifactScoreTypeOverrideRegistry {
  ArtifactScoreTypeOverrideRegistry({ArtifactScoreTypeOverrideLoader? loader})
    : _loader = loader;

  static final ArtifactScoreTypeOverrideRegistry instance =
      ArtifactScoreTypeOverrideRegistry();

  ArtifactScoreTypeOverrideLoader? _loader;
  Map<String, ArtifactScoreType> _byName = const {};
  bool _loaded = false;

  static void configureLoader(ArtifactScoreTypeOverrideLoader loader) {
    instance._loader = loader;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final loader = _loader;
    if (loader == null) {
      throw StateError(
        'ArtifactScoreTypeOverrideRegistry loader is not configured.',
      );
    }
    _byName = await loader();
    _loaded = true;
  }

  /// テスト・CLI 用: 明示的に上書きマップを注入する。
  void useOverridesForTest(Map<String, ArtifactScoreType> byName) {
    _byName = byName;
    _loaded = true;
  }

  void resetForTest() {
    _byName = const {};
    _loaded = false;
  }

  ArtifactScoreType? lookupByName(String name) => _byName[name];

  Map<String, ArtifactScoreType> get byName => Map.unmodifiable(_byName);
}
