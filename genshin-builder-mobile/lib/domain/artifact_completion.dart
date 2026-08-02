import 'artifact_config.dart';
import 'artifact_score.dart';
import 'artifact_score_weights.dart';
import 'models/artifact_state.dart';

/// 部位ごとの完成率（0〜100）と全体平均。
class ArtifactCompletionReport {
  const ArtifactCompletionReport({
    required this.overallPercent,
    required this.bySlot,
  });

  final double overallPercent;
  final Map<ArtifactSlotKey, double> bySlot;
}

/// 装備済み判定（セット名・アイコン・レベル・サブステのいずれか）。
bool isArtifactPieceEquipped(ArtifactPiece piece) {
  if (piece.setName.trim().isNotEmpty) return true;
  if (piece.iconUrl != null && piece.iconUrl!.trim().isNotEmpty) return true;
  if (piece.level > 0) return true;
  return piece.substats.any((s) => s.stat.trim().isNotEmpty);
}

/// 参考スコア（この値でスコア寄与が上限）。既存スコア系と独立した完成率用定数。
const double kArtifactCompletionReferenceScore = 40;

/// 部位完成率 0〜100。
///
/// 内訳: 装備 20 / レベル 25 / メイン 15 / サブ 25 / スコア 15
double calcArtifactPieceCompletionPercent(
  ArtifactPiece piece, {
  required ArtifactScoreType scoreType,
  ArtifactStatWeights? weights,
}) {
  if (!isArtifactPieceEquipped(piece)) return 0;

  final levelPart = 25.0 * (piece.level.clamp(0, 20) / 20.0);
  final mainPart = piece.mainStat.trim().isEmpty ? 0.0 : 15.0;
  final filledSubs = piece.substats
      .where((s) => s.stat.trim().isNotEmpty)
      .length
      .clamp(0, 4);
  final subPart = 25.0 * (filledSubs / 4.0);
  final score =
      weights == null
          ? calcArtifactPieceScore(piece, scoreType)
          : calcArtifactPieceScoreWithWeights(piece, weights);
  final scorePart =
      15.0 * (score / kArtifactCompletionReferenceScore).clamp(0.0, 1.0);

  return (20.0 + levelPart + mainPart + subPart + scorePart).clamp(0.0, 100.0);
}

ArtifactCompletionReport calcArtifactCompletionReport(
  ArtifactState artifacts, {
  required ArtifactScoreType scoreType,
  ArtifactStatWeights? weights,
}) {
  final bySlot = <ArtifactSlotKey, double>{};
  var sum = 0.0;
  for (final slot in artifactSlotOrder) {
    final piece = artifacts[slot] ?? createEmptyArtifactPiece();
    final pct = calcArtifactPieceCompletionPercent(
      piece,
      scoreType: scoreType,
      weights: weights,
    );
    bySlot[slot] = _round1(pct);
    sum += pct;
  }
  return ArtifactCompletionReport(
    overallPercent: _round1(sum / artifactSlotOrder.length),
    bySlot: bySlot,
  );
}

double _round1(double value) => (value * 10).roundToDouble() / 10;
