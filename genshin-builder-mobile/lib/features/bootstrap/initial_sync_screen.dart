import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/user_facing_error.dart';
import '../../data/models/sync_status.dart';
import '../../data/sync/master_sync_runner.dart';
import '../../providers/app_providers.dart';
import '../../providers/background_master_repair_provider.dart';

/// 起動時ブートストラップ
///
/// - キャラ 0 件のみブロッキング同期（アイコン等は Home 後）
/// - ローカルありなら即ホーム（probe は BackgroundMasterRepair）
class InitialSyncScreen extends ConsumerStatefulWidget {
  const InitialSyncScreen({super.key});

  @override
  ConsumerState<InitialSyncScreen> createState() => _InitialSyncScreenState();
}

class _InitialSyncScreenState extends ConsumerState<InitialSyncScreen> {
  bool _running = false;
  bool _navigatedHome = false;
  String? _error;
  String? _subtitle;
  SyncProgress? _syncProgress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _goHome() async {
    if (!mounted || _navigatedHome) return;
    _navigatedHome = true;
    context.go('/');
  }

  Future<void> _bootstrap() async {
    if (_running || _navigatedHome) return;

    final status = await ref.read(syncStatusProvider.future);
    if (!mounted) return;

    if (!status.requiresBlockingBootstrap) {
      await _goHome();
      return;
    }

    setState(() {
      _subtitle = 'キャラ・武器・素材のマスタデータを取得しています。';
    });
    await _runBlockingSync();
  }

  Future<void> _runBlockingSync() async {
    if (_navigatedHome) return;
    setState(() {
      _running = true;
      _error = null;
      _syncProgress = null;
    });

    try {
      final result = await runMasterDataSync(
        ref,
        onProgress: (p) {
          if (mounted) setState(() => _syncProgress = p);
        },
      );

      if (!mounted) return;

      if (result.characters == 0) {
        if (result.hasErrors) {
          logAppError(result.errors.join('; '), null, 'initialSync');
        }
        setState(() {
          _error = result.hasErrors
              ? userFacingSyncErrors(result.errors)
              : 'キャラデータを取得できませんでした。ネットワーク接続を確認してください。';
        });
        return;
      }

      // 成功時のみ — スキップ/失敗では呼ばない
      ref
          .read(backgroundMasterRepairProvider)
          .markMasterSyncCompletedDuringBootstrap();
      await _goHome();
    } catch (e, st) {
      logAppError(e, st, 'initialSync');
      if (mounted) {
        setState(() =>
            _error = '同期に失敗しました。ネットワーク接続を確認して再試行してください。');
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          if (_error == null) {
            _syncProgress = null;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.cloud_download_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'データ同期',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _subtitle ??
                    'キャラ・武器・素材のマスタデータを取得しています。'
                        '初回のみ数分かかることがあります。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_syncProgress != null) ...[
                Text(
                  _syncProgress!.displayLabel,
                  style: theme.textTheme.titleSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _syncProgress!.displayFraction,
                ),
              ] else if (_running) ...[
                const Center(child: CircularProgressIndicator()),
              ],
              if (_error != null) ...[
                const SizedBox(height: 24),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _running ? null : _runBlockingSync,
                  child: const Text('再試行'),
                ),
                TextButton(
                  onPressed: _running
                      ? null
                      : () {
                          // スキップは同期済み扱いにしない
                          _goHome();
                        },
                  child: const Text('スキップして続行'),
                ),
              ],
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
