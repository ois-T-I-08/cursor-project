import '../character_stats.dart';
import 'guide_insight.dart';

export 'guide_insight.dart';

enum BuildRecommendationOrigin { singleVideo, merged }

bool isSafeYoutubeGuideUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty) {
    return false;
  }
  final host = uri.host.toLowerCase();
  return const {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'youtu.be',
  }.contains(host);
}

class BuildRecommendationSource {
  const BuildRecommendationSource({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.sourceUrl,
    this.id,
    this.publishedAt,
    this.channelId,
    this.reviewedAt,
    this.gameVersion,
  });

  /// 公開 API の sources[].id（citationId 参照用）
  final String? id;
  final String videoId;
  final String title;
  final String channelTitle;
  final String sourceUrl;
  final DateTime? publishedAt;
  final String? channelId;
  final DateTime? reviewedAt;
  final String? gameVersion;

  GuideCitation toCitation() => GuideCitation(
    videoId: videoId.isEmpty ? null : videoId,
    videoTitle: title.isEmpty ? null : title,
    channelId: channelId,
    channelName: channelTitle.isEmpty ? null : channelTitle,
    publishedAt: publishedAt,
    reviewedAt: reviewedAt,
    gameVersion: gameVersion,
    sourceUrl: sourceUrl.isEmpty ? null : sourceUrl,
  );
}

class BuildRecommendationEvidence {
  const BuildRecommendationEvidence({
    required this.fieldPath,
    required this.exactVisibleText,
    required this.videoId,
    required this.startSeconds,
    required this.endSeconds,
  });

  final String fieldPath;
  final String exactVisibleText;
  final String videoId;
  final double startSeconds;
  final double endSeconds;
}

class BuildStatTarget {
  const BuildStatTarget({
    required this.stat,
    this.recommended,
    this.min,
    this.max,
    this.unit,
  });

  final StatKey stat;
  final double? recommended;
  final double? min;
  final double? max;
  final String? unit;
}

class CharacterBuildRecommendation {
  const CharacterBuildRecommendation({
    required this.characterId,
    required this.label,
    required this.origin,
    required this.overallConfidence,
    required this.targets,
    required this.substatPriority,
    required this.caveats,
    required this.sources,
    required this.evidence,
    this.mainStats = const [],
    this.weapons = const [],
    this.artifactRecommendations = const [],
    this.lastVerifiedAt,
    this.publishedAt,
    this.role,
    this.teamArchetype,
    this.weaponPreference,
    this.notes,
    this.investmentPriority = InvestmentPriority.none,
    this.gameVersion,
  });

  final String characterId;
  final String label;
  final BuildRecommendationOrigin origin;

  /// 情報の信頼度。育成優先度とは別概念。
  final double overallConfidence;
  final List<BuildStatTarget> targets;
  final List<StatKey> substatPriority;
  final List<String> caveats;
  final List<BuildRecommendationSource> sources;
  final List<BuildRecommendationEvidence> evidence;
  final List<GuideMainStatRecommendation> mainStats;
  final List<GuideWeaponRecommendation> weapons;
  final List<GuideArtifactRecommendation> artifactRecommendations;
  final DateTime? lastVerifiedAt;
  final DateTime? publishedAt;
  final String? role;
  final String? teamArchetype;

  /// 旧 API 互換。構造化 [weapons] が空のときだけ legacy 候補生成に使う。
  final String? weaponPreference;
  final String? notes;

  /// API 明示値のみ。未設定・未知は [InvestmentPriority.none]。
  final InvestmentPriority investmentPriority;
  final String? gameVersion;

  /// 構造化優先、なければ legacy `weaponPreference`。
  List<GuideWeaponRecommendation> get youtubeWeapons => resolveYoutubeWeapons(
    structured: weapons,
    legacyWeaponPreference: weaponPreference,
  );

  /// 鮮度表示用（「最新」とは断定しない）
  String? get freshnessCaption => formatFreshnessCaption(
    gameVersion: gameVersion,
    reviewedAt: lastVerifiedAt,
  );
}

enum BuildRecommendationFailure {
  notConfigured,
  notFound,
  timeout,
  networkError,
  invalidResponse,
}

class BuildRecommendationException implements Exception {
  const BuildRecommendationException(this.failure);

  final BuildRecommendationFailure failure;

  @override
  String toString() => 'BuildRecommendationException($failure)';
}

enum StatCompareVerdict { below, within, above, unknown }

StatCompareVerdict compareStatToTarget({
  required double current,
  required BuildStatTarget target,
}) {
  final min = target.min;
  final max = target.max;
  final recommended = target.recommended;
  if (min != null && max != null) {
    if (current < min) return StatCompareVerdict.below;
    if (current > max) return StatCompareVerdict.above;
    return StatCompareVerdict.within;
  }
  if (recommended != null) {
    final tol = recommended.abs() * 0.05 + 0.5;
    if (current < recommended - tol) return StatCompareVerdict.below;
    if (current > recommended + tol) return StatCompareVerdict.above;
    return StatCompareVerdict.within;
  }
  if (min != null) {
    return current < min ? StatCompareVerdict.below : StatCompareVerdict.within;
  }
  if (max != null) {
    return current > max ? StatCompareVerdict.above : StatCompareVerdict.within;
  }
  return StatCompareVerdict.unknown;
}

StatKey? parseGuideStatKey(String raw) {
  switch (raw) {
    case 'hp':
      return StatKey.hp;
    case 'atk':
      return StatKey.atk;
    case 'def':
      return StatKey.def;
    case 'em':
      return StatKey.em;
    case 'critRate':
      return StatKey.critRate;
    case 'critDmg':
      return StatKey.critDmg;
    case 'er':
      return StatKey.er;
    case 'healing':
      return StatKey.healing;
    case 'elemDmg':
      return StatKey.elemDmg;
    case 'physDmg':
      return StatKey.physDmg;
    default:
      return null;
  }
}
