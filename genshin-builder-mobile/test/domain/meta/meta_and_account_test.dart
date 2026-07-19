import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_builder_mobile/application/sync/local_only_cloud_sync.dart';
import 'package:genshin_builder_mobile/domain/account/user_account.dart';
import 'package:genshin_builder_mobile/domain/meta/meta_ranking_source.dart';

void main() {
  test('LocalOnlyCloudSync returns local anonymous account', () async {
    final sync = LocalOnlyCloudSync(localUserId: 'local-1');
    final account = await sync.currentAccount();
    expect(account.id, 'local-1');
    expect(account.kind, AccountKind.localAnonymous);
    expect(account.isLocal, isTrue);

    final push = await sync.push();
    expect(push.ok, isTrue);
    final pull = await sync.pull();
    expect(pull.message, 'クラウド同期は未設定です');
  });

  test('MetaRankingSnapshot scoresById maps entries', () {
    final snap = MetaRankingSnapshot(
      contextId: '10000046',
      entries: const [
        MetaRankingEntry(entityId: 'w1', score: 0.5),
        MetaRankingEntry(entityId: 'w2', score: 0.25),
      ],
      source: 'test',
      fetchedAt: DateTime(2026, 1, 1),
    );
    expect(snap.scoresById['w1'], 0.5);
    expect(snap.scoresById['w2'], 0.25);
  });
}
