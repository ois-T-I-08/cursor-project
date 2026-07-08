import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/sync_status.dart';
import '../../providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _syncing = false;
  String? _lastMessage;
  SyncProgress? _syncProgress;

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _lastMessage = null;
      _syncProgress = null;
    });
    try {
      final service = await ref.read(masterSyncServiceProvider.future);
      final result = await service.syncMasterData(
        onProgress: (p) {
          if (mounted) setState(() => _syncProgress = p);
        },
      );
      ref.invalidate(charactersProvider);
      ref.invalidate(syncStatusProvider);
      ref.invalidate(lastSyncTimeProvider);
      ref.invalidate(aggregatedBookmarksProvider);
      ref.invalidate(materialsMapProvider);
      setState(() {
        _lastMessage = result.hasErrors
            ? '一部エラー: ${result.errors.join('; ')}'
            : '同期完了 — キャラ ${result.characters} / 武器 ${result.weapons} / '
                '素材 ${result.materials} · 突破 キャラ ${result.characterUpgrades} / '
                '武器 ${result.weaponUpgrades}';
      });
    } catch (e) {
      setState(() => _lastMessage = '同期失敗: $e');
    } finally {
      setState(() {
        _syncing = false;
        _syncProgress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final syncStatusAsync = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          syncStatusAsync.when(
            data: (status) => _SyncStatusBanner(status: status),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'マスターデータ同期',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Project Amber (gi.yatta.moe) からキャラ・武器・素材と突破データを取得します。'
                    '初回は武器突破の取得に数分かかることがあります。',
                  ),
                  const SizedBox(height: 8),
                  syncStatusAsync.when(
                    data: (s) => Text(
                      s.lastSyncedAt == null
                          ? '未同期'
                          : '最終同期: ${s.lastSyncedAt!.toLocal()}\n'
                              '突破データ: キャラ ${s.characterUpgrades}/${s.characters} · '
                              '武器 ${s.weaponUpgrades}/${s.weapons}',
                    ),
                    loading: () => const Text('…'),
                    error: (e, _) => Text('$e'),
                  ),
                  if (_syncing && _syncProgress != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _syncProgress!.phase.label +
                          (_syncProgress!.detail != null
                              ? ' — ${_syncProgress!.detail}'
                              : _syncProgress!.total > 0
                                  ? ' ${_syncProgress!.current}/${_syncProgress!.total}'
                                  : ''),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _syncProgress!.isIndeterminate
                          ? null
                          : _syncProgress!.fraction,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _syncing ? null : _sync,
                    icon: _syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download),
                    label: Text(_syncing ? '同期中…' : '今すぐ同期'),
                  ),
                  if (_lastMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_lastMessage!),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.link),
              title: const Text('HoYoLAB 連携'),
              subtitle: const Text('樹脂・デイリー・派遣の表示'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/hoyolab'),
            ),
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.warning_amber),
            title: Text('免責事項'),
            subtitle: Text(
              '本アプリは非公式ツールです。ゲームデータの正確性は保証されません。',
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusBanner extends StatelessWidget {
  const _SyncStatusBanner({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    late final Color bg;
    late final Color fg;
    late final String message;

    if (status.isUnsynced) {
      bg = colorScheme.tertiaryContainer;
      fg = colorScheme.onTertiaryContainer;
      message = 'ゲームデータが未同期です。「今すぐ同期」を実行してください。';
    } else if (status.needsInitialUpgradeSync) {
      bg = colorScheme.tertiaryContainer;
      fg = colorScheme.onTertiaryContainer;
      message =
          '一覧は同期済みですが突破データが未登録です。同期で必要素材を取得します（初回は数分かかることがあります）。';
    } else if (status.missingCharacterUpgrades > 0 ||
        status.missingWeaponUpgrades > 0) {
      bg = colorScheme.tertiaryContainer;
      fg = colorScheme.onTertiaryContainer;
      message =
          '突破データが不足しています（キャラ ${status.missingCharacterUpgrades} 件 / '
          '武器 ${status.missingWeaponUpgrades} 件）。同期で不足分を取得できます。';
    } else if (status.upgradeComplete) {
      bg = colorScheme.primaryContainer.withValues(alpha: 0.5);
      fg = colorScheme.onPrimaryContainer;
      message = '突破・EXPデータは揃っています。ゲーム更新後は通常同期で十分です。';
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: TextStyle(color: fg, fontSize: 14)),
    );
  }
}
