import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/sync_status.dart';
import '../../core/errors/user_facing_error.dart';
import '../../data/sync/background_master_repair.dart';
import '../../data/sync/master_sync_runner.dart';
import '../../platform/app_notification_settings_channel.dart';
import '../../providers/app_providers.dart';
import '../../providers/background_master_repair_provider.dart';
import '../../providers/hoyolab_home_providers.dart';
import '../../providers/hoyolab_reminder_providers.dart';
import '../shared/shell_menu_button.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _syncing = false;
  String? _lastMessage;
  SyncProgress? _syncProgress;
  bool _reminderBusy = false;
  bool? _osNotificationsEnabled;

  @override
  void initState() {
    super.initState();
    _refreshOsPermission();
  }

  Future<void> _refreshOsPermission() async {
    try {
      final scheduler = ref.read(notificationSchedulerProvider);
      final enabled = await scheduler.areNotificationsEnabled();
      if (mounted) setState(() => _osNotificationsEnabled = enabled);
    } catch (_) {
      if (mounted) setState(() => _osNotificationsEnabled = false);
    }
  }

  Future<void> _setResinReminder(bool enabled) async {
    if (_reminderBusy) return;
    setState(() => _reminderBusy = true);
    try {
      final store = await ref.read(reminderSettingsStoreProvider.future);
      final scheduler = ref.read(notificationSchedulerProvider);
      final coordinator =
          await ref.read(notificationScheduleCoordinatorProvider.future);

      if (enabled) {
        final granted = await scheduler.requestPermission();
        await _refreshOsPermission();
        await store.setResinEnabled(true);
        if (!granted) {
          if (mounted) {
            setState(
              () => _lastMessage =
                  '樹脂通知をONにしましたが、端末側で通知が許可されていません。',
            );
          }
          return;
        }
        // Fresh DailyNote only — do not reconcile from stale cache alone.
        try {
          await ref.read(dailyNoteProvider.notifier).refresh();
        } catch (_) {
          if (mounted) {
            setState(
              () => _lastMessage =
                  '樹脂通知をONにしました。次回のリアルタイムメモ取得後に予約します。',
            );
          }
        }
      } else {
        await store.setResinEnabled(false);
        await coordinator.onPreferencesChangedCancelIfDisabled();
      }
      ref.invalidate(reminderSettingsStoreProvider);
    } catch (e, st) {
      logAppError(e, st, 'settings.reminder.resin');
      if (mounted) {
        setState(() => _lastMessage = '通知設定の更新に失敗しました。');
      }
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }

  Future<void> _setExpeditionReminder(bool enabled) async {
    if (_reminderBusy) return;
    setState(() => _reminderBusy = true);
    try {
      final store = await ref.read(reminderSettingsStoreProvider.future);
      final scheduler = ref.read(notificationSchedulerProvider);
      final coordinator =
          await ref.read(notificationScheduleCoordinatorProvider.future);

      if (enabled) {
        final granted = await scheduler.requestPermission();
        await _refreshOsPermission();
        await store.setExpeditionEnabled(true);
        if (!granted) {
          if (mounted) {
            setState(
              () => _lastMessage =
                  '探索派遣通知をONにしましたが、端末側で通知が許可されていません。',
            );
          }
          return;
        }
        try {
          await ref.read(dailyNoteProvider.notifier).refresh();
        } catch (_) {
          if (mounted) {
            setState(
              () => _lastMessage =
                  '探索派遣通知をONにしました。次回のリアルタイムメモ取得後に予約します。',
            );
          }
        }
      } else {
        await store.setExpeditionEnabled(false);
        await coordinator.onPreferencesChangedCancelIfDisabled();
      }
      ref.invalidate(reminderSettingsStoreProvider);
    } catch (e, st) {
      logAppError(e, st, 'settings.reminder.expedition');
      if (mounted) {
        setState(() => _lastMessage = '通知設定の更新に失敗しました。');
      }
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }

  Future<void> _sync({bool fullUpgrade = false}) async {
    final repair = ref.read(backgroundMasterRepairProvider);
    if (repair.isBusy) {
      setState(() {
        _lastMessage = 'バックグラウンドで同期中です。完了後に再試行してください。';
      });
      return;
    }

    setState(() {
      _syncing = true;
      _lastMessage = null;
      _syncProgress = null;
    });
    try {
      final start = await repair.runManualExclusive(() async {
        final outcome = await runMasterSyncWithIconPreload(
          ref,
          preloadOnlyMissingIcons: !fullUpgrade,
          fullUpgrade: fullUpgrade,
          onProgress: (p) {
            if (mounted) setState(() => _syncProgress = p);
          },
        );
        final result = outcome.result;
        final iconMessage = outcome.iconsLoaded > 0
            ? ' · 新規アイコン ${outcome.iconsLoaded} 件'
            : ' · アイコンは取得済み';
        final modeLabel = fullUpgrade ? '完全再同期完了' : '同期完了';
        if (!mounted) return;
        setState(() {
          _lastMessage = result.hasErrors
              ? userFacingSyncErrors(result.errors)
              : '$modeLabel — キャラ ${result.characters} / 武器 ${result.weapons} / '
                  '素材 ${result.materials} · 突破 キャラ ${result.characterUpgrades} / '
                  '武器 ${result.weaponUpgrades}$iconMessage';
        });
        if (result.hasErrors) {
          logAppError(result.errors.join('; '), null, 'settings.sync');
        }
      });
      if (!mounted) return;
      if (start == ManualSyncStart.busy) {
        setState(() {
          _lastMessage = 'バックグラウンドで同期中です。完了後に再試行してください。';
        });
      }
    } catch (e, st) {
      logAppError(e, st, 'settings.sync');
      if (!mounted) return;
      setState(() => _lastMessage = '同期に失敗しました。再試行してください。');
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _syncProgress = null;
        });
      }
    }
  }

  Future<void> _confirmFullUpgrade() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('完全再同期'),
        content: const Text(
          '突破データをすべて再取得します。ゲーム側で素材要件が変わった場合に使います。'
          '通常の同期より時間がかかります（数分）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('実行'),
          ),
        ],
      ),
    );
    if (ok == true) await _sync(fullUpgrade: true);
  }

  @override
  Widget build(BuildContext context) {
    final syncStatusAsync = ref.watch(syncStatusProvider);
    final versionStatusAsync = ref.watch(versionStatusProvider);
    final reminderStoreAsync = ref.watch(reminderSettingsStoreProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        actions: const [ShellMenuButton()],
      ),
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
                    '通常同期は未取得・contentHash 空の突破に加え、既存突破を最大 15 件ずつランダム再取得します。'
                    '全件を確実に取り直す場合は完全再同期を使います。',
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
                    error: (e, _) => Text(userFacingError(e)),
                  ),
                  const SizedBox(height: 8),
                  versionStatusAsync.when(
                    data: (v) {
                      if (!v.hasAnyVersion) return const SizedBox.shrink();
                      final lines = <String>[
                        'データバージョン',
                        '・Master: ${_shortVersion(v.masterDataVersion)}',
                        '・Score: ${_shortVersion(v.artifactScoreWeightsVersion)}',
                      ];
                      if (v.updatedAt != null) {
                        lines.add('更新: ${v.updatedAt!.toLocal()}');
                      }
                      return Text(
                        lines.join('\n'),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  if (_syncing && _syncProgress != null) ...[
                    const SizedBox(height: 16),
                    Text(_syncProgress!.displayLabel),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _syncProgress!.displayFraction,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _syncing ? null : () => _sync(),
                    icon: _syncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download),
                    label: Text(_syncing ? '同期中…' : '今すぐ同期'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _syncing ? null : _confirmFullUpgrade,
                    icon: const Icon(Icons.refresh),
                    label: const Text('完全再同期（突破を全件再取得）'),
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
              onTap: () => context.push('/settings/hoyolab'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: reminderStoreAsync.when(
                data: (store) => FutureBuilder(
                  future: store.readPreferences(),
                  builder: (context, snap) {
                    final prefs = snap.data;
                    final resinOn = prefs?.resinEnabled ?? false;
                    final expeditionOn = prefs?.expeditionEnabled ?? false;
                    final osDenied = _osNotificationsEnabled == false;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          title: Text(
                            'ローカル通知',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: const Text(
                            '端末内の予約通知です。既定はOFFです。',
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('樹脂190到達'),
                          subtitle: const Text('天然樹脂が190以上になったとき'),
                          value: resinOn,
                          onChanged: _reminderBusy
                              ? null
                              : (v) => _setResinReminder(v),
                        ),
                        SwitchListTile(
                          title: const Text('探索派遣すべて完了'),
                          subtitle: const Text('派遣が5件とも完了したとき'),
                          value: expeditionOn,
                          onChanged: _reminderBusy
                              ? null
                              : (v) => _setExpeditionReminder(v),
                        ),
                        if (osDenied && (resinOn || expeditionOn)) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Text('端末側で通知が許可されていません'),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await AppNotificationSettingsChannel.open();
                                await _refreshOsPermission();
                              },
                              icon: const Icon(Icons.settings),
                              label: const Text('端末の通知設定を開く'),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
                error: (_, __) => const ListTile(
                  title: Text('通知設定を読み込めませんでした'),
                ),
              ),
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

String _shortVersion(String? value) {
  if (value == null || value.isEmpty) return '-';
  if (value.length <= 8) return value;
  return value.substring(0, 8);
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
