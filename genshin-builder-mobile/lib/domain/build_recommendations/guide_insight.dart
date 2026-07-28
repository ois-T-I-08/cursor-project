/// 攻略情報の出典区分（表示・データ双方で混同しない）
enum GuideInsightSource {
  akasha,
  youtube,
}

/// YouTube 由来の育成優先度（明示値のみ。信頼度からの推定はしない）
enum InvestmentPriority {
  high,
  medium,
  low,
  none,
}

extension InvestmentPriorityLabel on InvestmentPriority {
  String get label {
    switch (this) {
      case InvestmentPriority.high:
        return '高';
      case InvestmentPriority.medium:
        return '中';
      case InvestmentPriority.low:
        return '低';
      case InvestmentPriority.none:
        return 'データなし';
    }
  }

  String get fullLabel => '育成優先度　$label';
}

/// 明示の [investmentPriority] のみを解釈する。未知値は [InvestmentPriority.none]。
InvestmentPriority parseInvestmentPriority(String? raw) {
  final explicit = raw?.trim().toLowerCase();
  if (explicit == null || explicit.isEmpty) {
    return InvestmentPriority.none;
  }
  switch (explicit) {
    case 'high':
    case 's':
    case '高':
      return InvestmentPriority.high;
    case 'medium':
    case 'mid':
    case 'a':
    case '中':
      return InvestmentPriority.medium;
    case 'low':
    case 'b':
    case '低':
      return InvestmentPriority.low;
    case 'none':
    case 'なし':
      return InvestmentPriority.none;
    default:
      return InvestmentPriority.none;
  }
}

/// おすすめ度（順位とは別軸）
enum GuideRecommendationLevel {
  stronglyRecommended,
  recommended,
  situational,
  alternative,
}

GuideRecommendationLevel? parseGuideRecommendationLevel(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'strongly_recommended':
    case 'strong':
    case 's':
      return GuideRecommendationLevel.stronglyRecommended;
    case 'recommended':
    case 'a':
      return GuideRecommendationLevel.recommended;
    case 'situational':
    case 'conditional':
    case 'b':
      return GuideRecommendationLevel.situational;
    case 'alternative':
    case 'alt':
    case 'c':
      return GuideRecommendationLevel.alternative;
    default:
      return null;
  }
}

extension GuideRecommendationLevelLabel on GuideRecommendationLevel {
  String get label {
    switch (this) {
      case GuideRecommendationLevel.stronglyRecommended:
        return '特におすすめ';
      case GuideRecommendationLevel.recommended:
        return 'おすすめ';
      case GuideRecommendationLevel.situational:
        return '状況次第';
      case GuideRecommendationLevel.alternative:
        return '代替';
    }
  }
}

/// 候補単位の出典（動画メタ）
class GuideCitation {
  const GuideCitation({
    this.videoId,
    this.videoTitle,
    this.channelId,
    this.channelName,
    this.publishedAt,
    this.reviewedAt,
    this.gameVersion,
    this.sourceUrl,
  });

  final String? videoId;
  final String? videoTitle;
  final String? channelId;
  final String? channelName;
  final DateTime? publishedAt;
  final DateTime? reviewedAt;
  final String? gameVersion;
  final String? sourceUrl;

  bool get hasAnyField =>
      (videoId != null && videoId!.isNotEmpty) ||
      (videoTitle != null && videoTitle!.isNotEmpty) ||
      (channelId != null && channelId!.isNotEmpty) ||
      (channelName != null && channelName!.isNotEmpty) ||
      publishedAt != null ||
      reviewedAt != null ||
      (gameVersion != null && gameVersion!.isNotEmpty) ||
      (sourceUrl != null && sourceUrl!.isNotEmpty);

  String? get caption {
    final parts = <String>[];
    if (channelName != null && channelName!.trim().isNotEmpty) {
      parts.add(channelName!.trim());
    }
    if (videoTitle != null && videoTitle!.trim().isNotEmpty) {
      parts.add(videoTitle!.trim());
    }
    final freshness = formatFreshnessCaption(
      gameVersion: gameVersion,
      reviewedAt: reviewedAt ?? publishedAt,
    );
    if (freshness != null) parts.add(freshness);
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// 武器候補の由来（構造化 API vs 旧文字列）
enum GuideWeaponDataOrigin {
  structured,
  legacyPreference,
}

/// YouTube おすすめ武器（可能な限り weaponId 基準）
class GuideWeaponRecommendation {
  const GuideWeaponRecommendation({
    this.weaponId,
    this.displayName,
    this.rank,
    this.recommendationLevel,
    this.reason,
    this.conditions = const [],
    this.role,
    this.source = GuideInsightSource.youtube,
    this.citation,
    this.dataOrigin = GuideWeaponDataOrigin.structured,
  });

  final String? weaponId;
  final String? displayName;
  final int? rank;
  final GuideRecommendationLevel? recommendationLevel;
  final String? reason;
  final List<String> conditions;
  final String? role;
  final GuideInsightSource source;
  final GuideCitation? citation;
  final GuideWeaponDataOrigin dataOrigin;

  bool get isLegacy => dataOrigin == GuideWeaponDataOrigin.legacyPreference;
}

/// 聖遺物セット構成の1パート（例: 2セット / 4セット）
class GuideArtifactSetPart {
  const GuideArtifactSetPart({
    required this.setId,
    required this.pieces,
  });

  final String setId;

  /// 必要部位数（通常 2 または 4）
  final int pieces;
}

/// YouTube おすすめ聖遺物構成
class GuideArtifactRecommendation {
  const GuideArtifactRecommendation({
    required this.sets,
    this.rank,
    this.recommendationLevel,
    this.reason,
    this.conditions = const [],
    this.role,
    this.source = GuideInsightSource.youtube,
    this.citation,
    this.isAlternative = false,
  });

  final List<GuideArtifactSetPart> sets;
  final int? rank;
  final GuideRecommendationLevel? recommendationLevel;
  final String? reason;
  final List<String> conditions;
  final String? role;
  final GuideInsightSource source;
  final GuideCitation? citation;
  final bool isAlternative;
}

enum GuideArtifactSlot { sands, goblet, circlet }

extension GuideArtifactSlotLabel on GuideArtifactSlot {
  String get label {
    switch (this) {
      case GuideArtifactSlot.sands:
        return '時計';
      case GuideArtifactSlot.goblet:
        return '杯';
      case GuideArtifactSlot.circlet:
        return '冠';
    }
  }
}

/// YouTube 由来メインステータス候補（第一候補 + 代替）
class GuideMainStatRecommendation {
  const GuideMainStatRecommendation({
    required this.slot,
    required this.candidates,
    this.condition,
    this.citation,
  });

  final GuideArtifactSlot slot;

  /// 先頭が第一候補、以降が代替
  final List<String> candidates;
  final String? condition;
  final GuideCitation? citation;

  String? get primary => candidates.isEmpty ? null : candidates.first;
  List<String> get alternatives =>
      candidates.length <= 1 ? const [] : candidates.sublist(1);
}

/// 旧 `weaponPreference` 自由記述から武器名候補を安全に分割する（legacy 専用）
List<String> parseWeaponPreferenceNames(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(RegExp(r'[,、/｜|\n]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty && e.length <= 64)
      .take(8)
      .toList();
}

/// 構造化リストが空のときだけ legacy 文字列から候補を生成する。
List<GuideWeaponRecommendation> resolveYoutubeWeapons({
  required List<GuideWeaponRecommendation> structured,
  String? legacyWeaponPreference,
}) {
  if (structured.isNotEmpty) return structured;
  final names = parseWeaponPreferenceNames(legacyWeaponPreference);
  return [
    for (var i = 0; i < names.length; i++)
      GuideWeaponRecommendation(
        displayName: names[i],
        rank: i + 1,
        dataOrigin: GuideWeaponDataOrigin.legacyPreference,
      ),
  ];
}

/// ゲームバージョンを数値タプルへ（辞書順比較はしない）
List<int>? parseGameVersionParts(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'^[Vv]er\.?\s*'), '');
  s = s.replaceFirst(RegExp(r'時点$'), '').trim();
  final match = RegExp(r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(s);
  if (match == null) return null;
  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2) ?? '0'),
    int.parse(match.group(3) ?? '0'),
  ];
}

int? compareGameVersions(String? a, String? b) {
  final pa = parseGameVersionParts(a);
  final pb = parseGameVersionParts(b);
  if (pa == null || pb == null) return null;
  for (var i = 0; i < 3; i++) {
    final d = pa[i].compareTo(pb[i]);
    if (d != 0) return d;
  }
  return 0;
}

/// 鮮度表示。アプリ側で現在バージョンを判断できない場合は「最新」と断定しない。
String? formatFreshnessCaption({
  String? gameVersion,
  DateTime? reviewedAt,
  String? currentGameVersion,
}) {
  final ver = gameVersion?.trim();
  final hasVersion = ver != null && ver.isNotEmpty;
  if (!hasVersion && reviewedAt == null) {
    return '対象バージョン不明';
  }

  final parts = <String>[];
  if (hasVersion) {
    final lower = ver.toLowerCase();
    final normalized = lower.startsWith('ver') ? ver : 'Ver.$ver';
    final stamped = normalized.contains('時点') ? normalized : '$normalized時点';
    parts.add(stamped);

    final cmp = compareGameVersions(ver, currentGameVersion);
    if (cmp != null && cmp < 0) {
      parts.add('古い情報の可能性があります');
    }
  }

  if (reviewedAt != null) {
    final d = reviewedAt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    parts.add('更新日：$y/$m/$day');
  }

  return parts.join(' · ');
}
