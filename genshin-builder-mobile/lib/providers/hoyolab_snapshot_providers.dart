import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hoyolab/hoyolab_home_disk_cache.dart';
import '../data/hoyolab/models/daily_note.dart';
import '../domain/account/snapshot_supplement.dart';
import 'app_providers.dart';
import 'hoyolab_providers.dart' show hoyolabSessionProvider;

/// Cached-only daily note — never triggers network requests.
/// Returns null when no cached data exists.
final cachedDailyNoteProvider = FutureProvider<DailyNote?>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final cache = HoyolabHomeDiskCache(AppDatabaseSettingsStore(db));
  final session = await ref.watch(hoyolabSessionProvider.future);
  if (!session.isLinked) return null;
  final entry = await cache.readDailyNote(session.uid!);
  return entry?.data;
});

/// Build AccountSnapshotSupplement from cache only — no network.
Future<AccountSnapshotSupplement> buildSnapshotSupplement(Ref ref) async {
  final dailyNote = ref.watch(cachedDailyNoteProvider).valueOrNull;
  if (dailyNote == null) return const AccountSnapshotSupplement();

  return AccountSnapshotSupplement(
    currentResin: dailyNote.currentResin,
    maxResin: dailyNote.maxResin,
    acquiredAt: DateTime.now(),
    status: SnapshotSupplementStatus.linked,
  );
}
