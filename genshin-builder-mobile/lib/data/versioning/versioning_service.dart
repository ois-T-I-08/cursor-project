import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../artifact_score/artifact_score_weight_repository.dart';
import '../db/app_database.dart';
import '../models/version_status.dart';

const masterDataVersionKey = 'version_master_data';
const artifactScoreWeightsVersionKey = 'version_artifact_score_weights';
const versionUpdatedAtKey = 'version_updated_at';

class VersioningService {
  VersioningService({
    required AppDatabase db,
    required ArtifactScoreWeightRepository weightRepository,
  })  : _db = db,
        _weightRepository = weightRepository;

  final AppDatabase _db;
  final ArtifactScoreWeightRepository _weightRepository;

  Future<VersionStatus> updateAndPersistVersions() async {
    final master = await _buildMasterDataVersion();
    final weights = await _weightRepository.currentVersionToken();
    final now = DateTime.now();

    await _db.setSetting(masterDataVersionKey, master);
    await _db.setSetting(artifactScoreWeightsVersionKey, weights);
    await _db.setSetting(versionUpdatedAtKey, now.toIso8601String());

    return VersionStatus(
      masterDataVersion: master,
      artifactScoreWeightsVersion: weights,
      updatedAt: now,
    );
  }

  Future<VersionStatus> readPersistedStatus() async {
    final master = await _db.getSetting(masterDataVersionKey);
    final weights = await _db.getSetting(artifactScoreWeightsVersionKey);
    final updatedAtRaw = await _db.getSetting(versionUpdatedAtKey);
    return VersionStatus(
      masterDataVersion: master,
      artifactScoreWeightsVersion: weights,
      updatedAt: updatedAtRaw == null ? null : DateTime.tryParse(updatedAtRaw),
    );
  }

  Future<String> _buildMasterDataVersion() async {
    final characters = await _db.getAllCharacters();
    final weapons = await _db.getAllWeapons();
    final materials = await _db.getAllMaterials();
    final characterUpgradeIds = await _db.getSyncedCharacterUpgradeIds();
    final weaponUpgradeIds = await _db.getSyncedWeaponUpgradeIds();
    final levelExpSegments = await _db.countLevelExpSegments();

    final payload = jsonEncode({
      'characters': characters.map((c) => [c.id, c.scoreType]).toList(),
      'weapons': weapons.map((w) => [w.id, w.rarity]).toList(),
      'materials': materials.map((m) => [m.id, m.rarity]).toList(),
      'characterUpgradeIds': characterUpgradeIds.toList()..sort(),
      'weaponUpgradeIds': weaponUpgradeIds.toList()..sort(),
      'levelExpSegments': levelExpSegments,
    });
    return md5.convert(utf8.encode(payload)).toString();
  }
}
