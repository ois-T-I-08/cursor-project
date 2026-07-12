/// 設定画面の同期状態（Web `getSyncStatus` 相当）
class SyncStatus {
  const SyncStatus({
    required this.characters,
    required this.weapons,
    required this.materials,
    required this.characterUpgrades,
    required this.weaponUpgrades,
    required this.levelExpSegments,
    this.lastSyncedAt,
  });

  final int characters;
  final int weapons;
  final int materials;
  final int characterUpgrades;
  final int weaponUpgrades;
  final int levelExpSegments;
  final DateTime? lastSyncedAt;

  int get missingCharacterUpgrades =>
      (characters - characterUpgrades).clamp(0, characters);

  int get missingWeaponUpgrades =>
      (weapons - weaponUpgrades).clamp(0, weapons);

  bool get expTableReady => levelExpSegments >= 32;

  bool get isUnsynced => characters == 0;

  bool get needsInitialUpgradeSync =>
      characters > 0 && characterUpgrades == 0;

  /// ローカルにマスタはあるが突破データが不足（新キャラ追加後など）
  bool get hasMissingUpgrades =>
      missingCharacterUpgrades > 0 || missingWeaponUpgrades > 0;

  /// ホーム描画前にマスタ同期を await する必要があるか（キャラ 0 件のみ）
  bool get requiresBlockingBootstrap => characters == 0;

  /// ホーム表示後にバックグラウンド修復してよい状態か
  bool get needsBackgroundRepair =>
      needsInitialUpgradeSync ||
      hasMissingUpgrades ||
      !expTableReady ||
      (characters > 0 && weapons == 0) ||
      (characters > 0 && materials == 0);

  /// 互換: 「何か同期した方がよい」広い判定。
  /// InitialSyncScreen の起動ゲートには使わない（[requiresBlockingBootstrap] を使う）。
  bool get shouldAutoSyncOnLaunch =>
      requiresBlockingBootstrap || needsBackgroundRepair;

  bool get upgradeComplete =>
      !isUnsynced &&
      missingCharacterUpgrades == 0 &&
      missingWeaponUpgrades == 0 &&
      expTableReady;
}

/// 同期中の進捗（設定画面のプログレス表示用）
class SyncProgress {
  const SyncProgress({
    required this.phase,
    required this.current,
    required this.total,
    this.detail,
  });

  final SyncPhase phase;
  final int current;
  final int total;
  final String? detail;

  double get fraction => total <= 0 ? 0 : (current / total).clamp(0.0, 1.0);

  bool get isIndeterminate =>
      total <= 0 && phase != SyncPhase.iconPreload;
}

extension SyncProgressDisplay on SyncProgress {
  String get displayLabel {
    if (phase == SyncPhase.iconPreload) {
      if (total <= 0) {
        if (detail == '取得済み') return 'アイコンはすべて取得済み';
        return 'アイコン読み込みを準備中…';
      }
      return 'アイコン読み込み $current/$total';
    }
    if (detail != null) return '${phase.label} — $detail';
    if (total > 0) return '${phase.label} $current/$total';
    return phase.label;
  }

  double? get displayFraction {
    if (total <= 0) return null;
    return fraction;
  }
}

enum SyncPhase {
  master,
  expMaterials,
  levelExp,
  characterUpgrades,
  weaponUpgrades,
  iconPreload,
  finishing,
}

extension SyncPhaseLabel on SyncPhase {
  String get label => switch (this) {
        SyncPhase.master => 'マスタ一覧',
        SyncPhase.expMaterials => '経験値素材',
        SyncPhase.levelExp => 'レベルEXP表',
        SyncPhase.characterUpgrades => 'キャラ突破データ',
        SyncPhase.weaponUpgrades => '武器突破データ',
        SyncPhase.iconPreload => 'アイコン読み込み',
        SyncPhase.finishing => '完了処理',
      };
}
