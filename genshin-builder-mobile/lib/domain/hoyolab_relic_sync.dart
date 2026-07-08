import '../data/hoyolab/models/game_record.dart';
import 'artifact_config.dart';
import 'hoyolab_stat_normalize.dart';
import 'models/artifact_state.dart';

double parseStatValue(String raw) {
  final cleaned = raw.replaceAll('%', '').trim();
  return double.tryParse(cleaned) ?? 0;
}

List<ArtifactSubstat> substatsFromGameRecord(List<GameRecordProp> props) {
  return props
      .map((p) {
        final label = normalizeSubStatLabel(p.label) ?? p.label;
        return ArtifactSubstat(
          stat: label,
          value: parseStatValue(p.value),
        );
      })
      .where((s) => s.stat.isNotEmpty && subStatOptions.contains(s.stat))
      .toList();
}

/// HoYoLAB の聖遺物からセット名・レベル・メインステを反映。
/// サブステは未入力時のみ API 値を補完。
ArtifactState mergeRelicsFromHoyolab({
  required ArtifactState local,
  required List<GameRecordRelic> relics,
}) {
  var result = copyArtifactState(local);

  for (final relic in relics) {
    final slot = artifactSlotFromPosName(relic.posName);
    if (slot == null) continue;

    final piece = result[slot] ?? createEmptyArtifactPiece();
    var updated = piece.copyWith(
      setName: relic.setName.isNotEmpty ? relic.setName : piece.setName,
      level: relic.level > 0 ? relic.level : piece.level,
      iconUrl: relic.iconUrl ?? piece.iconUrl,
      name: relic.name.isNotEmpty ? relic.name : piece.name,
    );

    if (relic.mainStat != null) {
      final mainStat = normalizeMainStatForSlot(relic.mainStat!.label, slot);
      if (mainStat != null) {
        updated = updated.copyWith(mainStat: mainStat);
      }
    }

    if (piece.substats.isEmpty && relic.subStats.isNotEmpty) {
      updated = updated.copyWith(substats: substatsFromGameRecord(relic.subStats));
    }

    result = updateArtifactPiece(result, slot, updated);
  }

  return result;
}
