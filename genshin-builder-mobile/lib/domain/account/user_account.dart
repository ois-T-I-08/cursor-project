/// ローカル / 将来のクラウドアカウント境界。
library;

enum AccountKind { localAnonymous, remote }

class UserAccount {
  const UserAccount({
    required this.id,
    this.displayName,
    this.kind = AccountKind.localAnonymous,
  });

  final String id;
  final String? displayName;
  final AccountKind kind;

  bool get isLocal => kind == AccountKind.localAnonymous;
}

/// クラウド同期の契約（未接続時は no-op 実装を使う）。
abstract class CloudSyncPort {
  /// 端末の匿名/ログインアカウント
  Future<UserAccount> currentAccount();

  /// リモートへプッシュ（未実装時は何もしない）
  Future<CloudSyncResult> push();

  /// リモートからプル
  Future<CloudSyncResult> pull();
}

class CloudSyncResult {
  const CloudSyncResult({
    required this.ok,
    this.message = '',
    this.pushed = 0,
    this.pulled = 0,
  });

  final bool ok;
  final String message;
  final int pushed;
  final int pulled;

  static const disabled = CloudSyncResult(
    ok: true,
    message: 'クラウド同期は未設定です',
  );
}
