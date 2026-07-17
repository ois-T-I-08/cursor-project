import '../../domain/account/user_account.dart';
import '../../domain/repositories/progress_repository.dart';

/// ローカル専用の CloudSyncPort。クラウド未接続時のデフォルト。
class LocalOnlyCloudSync implements CloudSyncPort {
  LocalOnlyCloudSync({
    required this.localUserId,
    ProgressRepository? progress,
  }) : _progress = progress;

  final String localUserId;
  final ProgressRepository? _progress;

  @override
  Future<UserAccount> currentAccount() async => UserAccount(
        id: localUserId,
        displayName: 'ローカル',
        kind: AccountKind.localAnonymous,
      );

  @override
  Future<CloudSyncResult> push() async {
    // 将来: progress / bookmarks をリモートへ
    final count = _progress == null
        ? 0
        : (await _progress.getAll(localUserId)).length;
    return CloudSyncResult(
      ok: true,
      message: 'ローカル専用モードです（リモートなし）。進捗 $count 件を端末に保持しています。',
      pushed: 0,
    );
  }

  @override
  Future<CloudSyncResult> pull() async => CloudSyncResult.disabled;
}
