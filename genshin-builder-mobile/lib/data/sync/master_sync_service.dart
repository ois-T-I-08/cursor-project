import '../amber/amber_api.dart';
import '../amber/amber_upgrade.dart';
import '../db/app_database.dart';
import '../models/sync_status.dart';

class SyncResult {
  SyncResult({
    required this.provider,
    this.characters = 0,
    this.weapons = 0,
    this.materials = 0,
    this.characterUpgrades = 0,
    this.weaponUpgrades = 0,
    this.levelExpSegments = 0,
    this.expMaterials = 0,
    this.skippedCharacterUpgrades = 0,
    this.skippedWeaponUpgrades = 0,
    List<String>? errors,
  }) : errors = errors ?? <String>[];

  final String provider;
  int characters;
  int weapons;
  int materials;
  int characterUpgrades;
  int weaponUpgrades;
  int levelExpSegments;
  int expMaterials;
  int skippedCharacterUpgrades;
  int skippedWeaponUpgrades;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() =>
      'Sync($provider): chars=$characters weapons=$weapons materials=$materials '
      'charUp=$characterUpgrades wpnUp=$weaponUpgrades '
      'expSeg=$levelExpSegments expMat=$expMaterials '
      'skipChar=$skippedCharacterUpgrades skipWpn=$skippedWeaponUpgrades '
      'errors=${errors.length}';
}

typedef SyncProgressCallback = void Function(SyncProgress progress);

/// マスターデータ同期（Web `sync.ts` + `sync-upgrade.ts` 相当）
class MasterSyncService {
  MasterSyncService({
    required AmberApi amberApi,
    required AppDatabase db,
    AmberUpgradeApi? upgradeApi,
    this.syncUpgradeDetails = true,
    this.fullUpgrade = false,
  })  : _amber = amberApi,
        _upgrade = upgradeApi ?? AmberUpgradeApi(),
        _db = db;

  final AmberApi _amber;
  final AmberUpgradeApi _upgrade;
  final AppDatabase _db;
  final bool syncUpgradeDetails;
  final bool fullUpgrade;

  static const _expMaterialCount = 6;
  static const _levelExpSegmentCount = 32;

  void _report(SyncProgressCallback? onProgress, SyncProgress progress) {
    onProgress?.call(progress);
  }

  Future<SyncResult> syncMasterData({SyncProgressCallback? onProgress}) async {
    final result = SyncResult(provider: AmberApi.name);

    _report(
      onProgress,
      const SyncProgress(phase: SyncPhase.master, current: 0, total: 3),
    );

    try {
      final characters = await _amber.fetchCharacters();
      await _db.upsertCharactersBatch(characters);
      result.characters = characters.length;
      _report(
        onProgress,
        const SyncProgress(phase: SyncPhase.master, current: 1, total: 3),
      );
    } catch (e) {
      result.errors.add('characters: $e');
    }

    try {
      final weapons = await _amber.fetchWeapons();
      await _db.upsertWeaponsBatch(weapons);
      result.weapons = weapons.length;
      _report(
        onProgress,
        const SyncProgress(phase: SyncPhase.master, current: 2, total: 3),
      );
    } catch (e) {
      result.errors.add('weapons: $e');
    }

    try {
      final materials = await _amber.fetchMaterials();
      await _db.upsertMaterialsBatch(materials);
      result.materials = materials.length;
      _report(
        onProgress,
        const SyncProgress(phase: SyncPhase.master, current: 3, total: 3),
      );
    } catch (e) {
      result.errors.add('materials: $e');
    }

    if (syncUpgradeDetails) {
      await _syncExpMaterials(result, onProgress);
      await _syncLevelExpSegments(result, onProgress);
      await _syncCharacterUpgrades(result, onProgress);
      await _syncWeaponUpgrades(result, onProgress);
    }

    _report(
      onProgress,
      const SyncProgress(phase: SyncPhase.finishing, current: 1, total: 1),
    );

    final status = result.hasErrors ? 'partial' : 'success';
    await _db.insertSyncLog(status, result.toString());

    return result;
  }

  Future<void> _syncExpMaterials(
    SyncResult result,
    SyncProgressCallback? onProgress,
  ) async {
    _report(
      onProgress,
      const SyncProgress(phase: SyncPhase.expMaterials, current: 0, total: 1),
    );
    try {
      final existing = await _db.countExpMaterials();
      if (!fullUpgrade && existing >= _expMaterialCount) {
        result.expMaterials = existing;
        _report(
          onProgress,
          const SyncProgress(
            phase: SyncPhase.expMaterials,
            current: 1,
            total: 1,
            detail: 'スキップ（取得済み）',
          ),
        );
        return;
      }

      final mats = await _upgrade.fetchLevelUpMaterials();
      for (final mat in mats) {
        await _db.updateMaterialExp(
          materialId: mat.materialId,
          expValue: mat.exp,
          expTarget: mat.targetType,
        );
      }
      result.expMaterials = mats.length;
      _report(
        onProgress,
        SyncProgress(
          phase: SyncPhase.expMaterials,
          current: 1,
          total: 1,
          detail: '${mats.length} 件',
        ),
      );
    } catch (e) {
      result.errors.add('expMaterials: $e');
    }
  }

  Future<void> _syncLevelExpSegments(
    SyncResult result,
    SyncProgressCallback? onProgress,
  ) async {
    _report(
      onProgress,
      const SyncProgress(phase: SyncPhase.levelExp, current: 0, total: 1),
    );
    try {
      final existing = await _db.countLevelExpSegments();
      if (!fullUpgrade && existing >= _levelExpSegmentCount) {
        result.levelExpSegments = existing;
        _report(
          onProgress,
          const SyncProgress(
            phase: SyncPhase.levelExp,
            current: 1,
            total: 1,
            detail: 'スキップ（取得済み）',
          ),
        );
        return;
      }

      final segments = _db.buildLevelExpSegments();
      await _db.upsertLevelExpSegments(segments);
      result.levelExpSegments = segments.length;
      _report(
        onProgress,
        SyncProgress(
          phase: SyncPhase.levelExp,
          current: 1,
          total: 1,
          detail: '${segments.length} 件',
        ),
      );
    } catch (e) {
      result.errors.add('levelExpSegments: $e');
    }
  }

  Future<void> _syncCharacterUpgrades(
    SyncResult result,
    SyncProgressCallback? onProgress,
  ) async {
    try {
      final allCharacters = await _db.getAllCharacters();
      final existingIds = fullUpgrade
          ? <String>{}
          : await _db.getSyncedCharacterUpgradeIds();

      final targetIds = fullUpgrade
          ? allCharacters.map((c) => c.id).toList()
          : allCharacters
              .where((c) => !existingIds.contains(c.id))
              .map((c) => c.id)
              .toList();

      result.skippedCharacterUpgrades =
          allCharacters.length - targetIds.length;

      _report(
        onProgress,
        SyncProgress(
          phase: SyncPhase.characterUpgrades,
          current: 0,
          total: targetIds.length,
          detail: targetIds.isEmpty ? 'スキップ（取得済み）' : null,
        ),
      );

      final upgrades = await _upgrade.mapWithConcurrency(
        targetIds,
        (id) async {
          final data = await _upgrade.fetchCharacterUpgrade(id);
          if (data == null) return null;
          return (
            characterId: id,
            promotes: data.promotes,
            talents: data.talents,
          );
        },
        onProgress: (completed, total) {
          _report(
            onProgress,
            SyncProgress(
              phase: SyncPhase.characterUpgrades,
              current: completed,
              total: total,
            ),
          );
        },
      );

      for (final upgrade in upgrades) {
        await _db.upsertCharacterUpgrade(
          characterId: upgrade.characterId,
          promotes: upgrade.promotes,
          talents: upgrade.talents,
        );
      }

      result.characterUpgrades =
          (await _db.getSyncedCharacterUpgradeIds()).length;
    } catch (e) {
      result.errors.add('characterUpgrades: $e');
    }
  }

  Future<void> _syncWeaponUpgrades(
    SyncResult result,
    SyncProgressCallback? onProgress,
  ) async {
    try {
      final allWeapons = await _db.getAllWeapons();
      final existingIds =
          fullUpgrade ? <String>{} : await _db.getSyncedWeaponUpgradeIds();

      final targetIds = fullUpgrade
          ? allWeapons.map((w) => w.id).toList()
          : allWeapons
              .where((w) => !existingIds.contains(w.id))
              .map((w) => w.id)
              .toList();

      result.skippedWeaponUpgrades = allWeapons.length - targetIds.length;

      _report(
        onProgress,
        SyncProgress(
          phase: SyncPhase.weaponUpgrades,
          current: 0,
          total: targetIds.length,
          detail: targetIds.isEmpty ? 'スキップ（取得済み）' : null,
        ),
      );

      final upgrades = await _upgrade.mapWithConcurrency(
        targetIds,
        (id) async {
          final data = await _upgrade.fetchWeaponUpgrade(id);
          if (data == null) return null;
          return (
            weaponId: id,
            promotes: data.promotes,
            levelUpItemIds: data.levelUpItemIds,
          );
        },
        onProgress: (completed, total) {
          _report(
            onProgress,
            SyncProgress(
              phase: SyncPhase.weaponUpgrades,
              current: completed,
              total: total,
            ),
          );
        },
      );

      for (final upgrade in upgrades) {
        await _db.upsertWeaponUpgrade(
          weaponId: upgrade.weaponId,
          promotes: upgrade.promotes,
          levelUpItemIds: upgrade.levelUpItemIds,
        );
      }

      result.weaponUpgrades = (await _db.getSyncedWeaponUpgradeIds()).length;
    } catch (e) {
      result.errors.add('weaponUpgrades: $e');
    }
  }
}
