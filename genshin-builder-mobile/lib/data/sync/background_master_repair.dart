import 'dart:async';

import '../models/sync_status.dart';
import 'master_content_probe.dart';
import 'master_sync_service.dart';

/// 手動同期の開始結果（BG 実行中は [busy]）
enum ManualSyncStart {
  busy,
  completed,
}

/// ホーム表示後のマスタ修復・後段処理（同一プロセスで冪等）
///
/// - [_inFlight]: 同時呼び出しの合流 / 手動との排他
/// - [_startedAfterHome]: Home 再生成や往復での再実行防止
/// - [_iconsStarted] / [_hoyolabPrefetchStarted]: 後段の一度きり
/// - [_masterSyncedDuringBootstrap]: 初回ブロッキング同期成功後の二重同期防止
/// - [_probeRunToken]: timeout 後の遅延 probe 結果を採用しない
class BackgroundMasterRepair {
  BackgroundMasterRepair({
    required this.loadSyncStatus,
    required this.runProbe,
    required this.runMasterSync,
    required this.preloadIcons,
    required this.backfillWeights,
    this.probeTimeout = const Duration(seconds: 15),
  });

  final Future<SyncStatus> Function() loadSyncStatus;
  final Future<MasterContentProbeResult> Function() runProbe;
  final Future<SyncResult> Function() runMasterSync;
  final Future<int> Function() preloadIcons;
  final Future<void> Function() backfillWeights;
  final Duration probeTimeout;

  Future<void>? _inFlight;
  bool _startedAfterHome = false;
  bool _iconsStarted = false;
  bool _hoyolabPrefetchStarted = false;
  bool _masterSyncedDuringBootstrap = false;
  int _probeRunToken = 0;

  /// テスト用
  bool get startedAfterHome => _startedAfterHome;
  bool get masterSyncedDuringBootstrap => _masterSyncedDuringBootstrap;
  bool get iconsStarted => _iconsStarted;
  bool get hoyolabPrefetchStarted => _hoyolabPrefetchStarted;
  int get probeRunToken => _probeRunToken;

  bool get isBusy => _inFlight != null;

  /// 初回ブロッキング MasterSync 成功時のみ呼ぶ（スキップ/失敗では呼がない）
  void markMasterSyncCompletedDuringBootstrap() {
    _masterSyncedDuringBootstrap = true;
  }

  /// 同一 ProviderScope / プロセス内で冪等。同時呼び出しは同じ Future へ合流。
  Future<void> ensureStartedAfterHome() {
    if (_startedAfterHome) {
      return _inFlight ?? Future<void>.value();
    }
    _startedAfterHome = true;

    if (_inFlight != null) {
      return _inFlight!;
    }

    final future = _runBackgroundPipeline();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
    return future;
  }

  /// BG 実行中は開始せず [ManualSyncStart.busy]。合流して成功扱いしない。
  Future<ManualSyncStart> runManualExclusive(
    Future<void> Function() action,
  ) async {
    if (_inFlight != null) {
      return ManualSyncStart.busy;
    }

    final future = action();
    _inFlight = future;
    try {
      await future;
      return ManualSyncStart.completed;
    } finally {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    }
  }

  /// HoYoLAB prefetch を同一起動で一度だけ開始する。
  void ensureHoyolabPrefetch(void Function() start) {
    if (_hoyolabPrefetchStarted) return;
    _hoyolabPrefetchStarted = true;
    start();
  }

  Future<void> _runBackgroundPipeline() async {
    if (!_masterSyncedDuringBootstrap) {
      await _maybeProbeAndSync();
    }
    await _runIconsOnce();
    await _runWeightsOnce();
  }

  Future<void> _maybeProbeAndSync() async {
    final status = await loadSyncStatus();
    var shouldSync = status.needsBackgroundRepair;

    if (!shouldSync) {
      final probe = await _runProbeWithTimeout();
      if (probe != null && probe.shouldSync) {
        shouldSync = true;
      }
    }

    if (!shouldSync) return;

    try {
      await runMasterSync();
    } catch (_) {
      // 既存ローカル維持。同一起動で自動リトライしない。
    }
  }

  /// timeout 後に遅延完了しても採用しない。
  Future<MasterContentProbeResult?> _runProbeWithTimeout() async {
    final token = ++_probeRunToken;
    final pending = runProbe();
    try {
      final result = await pending.timeout(probeTimeout);
      if (token != _probeRunToken) return null;
      return result;
    } on TimeoutException {
      // 遅延結果を無効化（後続の token 照合用）
      if (token == _probeRunToken) {
        _probeRunToken++;
      }
      // pending の完了は無視（then で sync しない）
      unawaited(pending.catchError((_) => const MasterContentProbeResult(
            shouldSync: false,
            reasons: [],
            error: 'ignored-after-timeout',
          )));
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _runIconsOnce() async {
    if (_iconsStarted) return;
    _iconsStarted = true;
    try {
      await preloadIcons();
    } catch (_) {
      // アイコン失敗は無視
    }
  }

  Future<void> _runWeightsOnce() async {
    try {
      await backfillWeights();
    } catch (_) {
      // weights 失敗は無視
    }
  }

  /// テスト: timeout 後に完了した probe Future を渡しても sync しないことを検証する用
  Future<MasterContentProbeResult?> debugRunProbeWithTimeoutForTest() =>
      _runProbeWithTimeout();
}
