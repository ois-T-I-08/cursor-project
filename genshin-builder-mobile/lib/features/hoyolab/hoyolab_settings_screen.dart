import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/feature_flags.dart';
import '../../core/errors/user_facing_error.dart';
import '../../data/hoyolab/hoyolab_exceptions.dart';
import '../../data/hoyolab/models/daily_note.dart';
import '../../providers/app_providers.dart';
import '../../providers/hoyolab_game_refresh.dart';
import '../../providers/hoyolab_home_providers.dart';
import '../../providers/hoyolab_game_providers.dart';
import '../../providers/hoyolab_providers.dart';
import 'hoyolab_login_screen.dart';
import 'widgets/hoyolab_disclaimer_banner.dart';

class HoyolabSettingsScreen extends ConsumerStatefulWidget {
  const HoyolabSettingsScreen({super.key});

  @override
  ConsumerState<HoyolabSettingsScreen> createState() =>
      _HoyolabSettingsScreenState();
}

class _HoyolabSettingsScreenState extends ConsumerState<HoyolabSettingsScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _refreshProviders() async {
    ref.invalidate(hoyolabSessionProvider);
    ref.invalidate(dailyNoteProvider);
    ref.invalidate(hoyolabRolesProvider);
    ref.invalidate(featureFlagsProvider);
    refreshAllHoyolabGameData(ref);
  }

  Future<void> _startLogin() async {
    final cookie = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const HoyolabLoginScreen()),
    );
    if (cookie == null || cookie.isEmpty || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final repo = await ref.read(hoyolabRepositoryProvider.future);
      await repo.completeLogin(cookie: cookie);
      await _refreshProviders();
      setState(() => _message = 'HoYoLAB 連携が完了しました');
    } on HoyolabApiException catch (e) {
      setState(() => _message = e.userMessage);
    } catch (e, st) {
      logAppError(e, st, 'hoyolab.login');
      setState(
        () => _message = userFacingError(
          e,
          fallback: '連携に失敗しました。ログイン状態を確認して再試行してください。',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('連携を解除'),
        content: const Text('保存された Cookie と UID 情報を削除します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('解除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final session = await ref.read(hoyolabSessionProvider.future);
      if (session.uid != null && session.uid!.isNotEmpty) {
        final diskCache = await ref.read(hoyolabHomeDiskCacheProvider.future);
        await diskCache.clearForUid(session.uid!);
        final discoveryStore =
            await ref.read(hoyolabCharacterDiscoveryStoreProvider.future);
        await discoveryStore.clearForUid(session.uid!);
      }
      final repo = await ref.read(hoyolabRepositoryProvider.future);
      await repo.disconnect();
      await _refreshProviders();
      setState(() => _message = '連携を解除しました');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectRole(List<HoyolabGameRole> roles, HoyolabGameRole? current) async {
    final selected = await showModalBottomSheet<HoyolabGameRole>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('ゲームアカウントを選択'),
            ),
            ...roles.map(
              (role) => ListTile(
                title: Text(role.nickname),
                subtitle: Text('UID ${role.uid} · ${role.region} · Lv.${role.level}'),
                trailing: current?.uid == role.uid
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, role),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;

    setState(() => _busy = true);
    try {
      final repo = await ref.read(hoyolabRepositoryProvider.future);
      await repo.selectRole(selected);
      await _refreshProviders();
      setState(() => _message = '${selected.nickname} を選択しました');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFeatureFlag(bool enabled) async {
    final db = await ref.read(appDatabaseProvider.future);
    await db.setSetting(
      FeatureFlags.hoyolabLinkEnabledKey,
      enabled.toString(),
    );
    await _refreshProviders();
    setState(() => _message = enabled ? 'HoYoLAB 連携を有効化' : 'HoYoLAB 連携を無効化');
  }

  @override
  Widget build(BuildContext context) {
    final flagsAsync = ref.watch(featureFlagsProvider);
    final sessionAsync = ref.watch(hoyolabSessionProvider);
    final rolesAsync = ref.watch(hoyolabRolesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('HoYoLAB 連携')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const HoyolabDisclaimerBanner(),
          const SizedBox(height: 16),
          flagsAsync.when(
            data: (flags) => SwitchListTile(
              title: const Text('HoYoLAB 連携を有効化'),
              subtitle: const Text('機能フラグ（Remote Config 相当）'),
              value: flags.hoyolabLinkEnabled,
              onChanged: _busy ? null : _toggleFeatureFlag,
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(userFacingError(e)),
          ),
          const SizedBox(height: 16),
          sessionAsync.when(
            data: (session) {
              if (!session.isLinked) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('未連携です。WebView で HoYoLAB にログインしてください。'),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : _startLogin,
                          icon: const Icon(Icons.login),
                          label: const Text('HoYoLAB でログイン'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '連携済み',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('UID: ${session.uid ?? '-'}'),
                      Text('サーバー: ${session.region ?? '-'}'),
                      if (session.nickname != null)
                        Text('ニックネーム: ${session.nickname}'),
                      const SizedBox(height: 16),
                      rolesAsync.when(
                        data: (roles) {
                          if (roles.length <= 1) return const SizedBox.shrink();
                          HoyolabGameRole? current;
                          for (final role in roles) {
                            if (role.uid == session.uid) {
                              current = role;
                              break;
                            }
                          }
                          return OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _selectRole(roles, current),
                            icon: const Icon(Icons.swap_horiz),
                            label: const Text('アカウント切替'),
                          );
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _disconnect,
                        icon: const Icon(Icons.link_off),
                        label: const Text('連携を解除'),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text(userFacingError(e)),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
