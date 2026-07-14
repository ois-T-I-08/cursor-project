import 'artifact_score_weight.dart';
import 'artifact_score_weight_source.dart';
import '../models/master_models.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class ArtifactScoreWeightRepository {
  ArtifactScoreWeightRepository(this._source);
  final ArtifactScoreWeightSource _source;

  Future<List<ArtifactScoreWeightProfile>> loadProfiles() async {
    return _source.loadProfiles();
  }

  Future<ArtifactScoreWeightProfile?> findByCharacterId(String characterId) async {
    final profiles = await loadProfiles();
    for (final profile in profiles) {
      if (profile.characterId == characterId) return profile;
    }
    return null;
  }

  /// 同期後に呼び出し、新キャラの重みが未登録ならリモート再取得を試みる。
  Future<List<String>> syncMissingCharacterProfiles(
    List<MasterCharacter> characters,
  ) async {
    var profiles = await loadProfiles();
    var profileIds = profiles.map((e) => e.characterId).toSet();
    var missing = characters
        .where((c) => !profileIds.contains(c.id))
        .map((c) => c.id)
        .toList(growable: false);

    if (missing.isNotEmpty && _source is RefreshableArtifactScoreWeightSource) {
      profiles =
          await _source.refreshProfiles();
      profileIds = profiles.map((e) => e.characterId).toSet();
      missing = characters
          .where((c) => !profileIds.contains(c.id))
          .map((c) => c.id)
          .toList(growable: false);
    }

    return missing;
  }

  Future<String> currentVersionToken() async {
    final profiles = await loadProfiles();
    final normalized = profiles
        .map(
          (p) => {
            'characterId': p.characterId,
            'name': p.name,
            'weights': p.weights.toJson(),
          },
        )
        .toList(growable: false)
      ..sort((a, b) => '${a['characterId']}'.compareTo('${b['characterId']}'));
    final raw = jsonEncode({'profiles': normalized});
    return md5.convert(utf8.encode(raw)).toString();
  }
}
