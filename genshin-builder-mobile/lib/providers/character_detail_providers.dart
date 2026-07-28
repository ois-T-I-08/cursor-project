import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/akasha/akasha_weapon_usage.dart';
import '../data/akasha/akasha_weapon_usage_repository.dart';
import '../data/amber/amber_detail_repository.dart';
import '../data/meta/akasha_weapon_meta_ranking_source.dart';
import '../domain/character_stats.dart';
import '../domain/meta/meta_ranking_source.dart';

export 'character_detail_notifier.dart'
    show characterDetailProvider, CharacterDetailNotifier;

/// Amber 詳細データ（スキル・曲線）のリポジトリ。メモリキャッシュを共有する
final amberDetailRepositoryProvider = Provider<AmberDetailRepository>((ref) {
  final repo = AmberDetailRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Akasha 公開ビルドからキャラ別武器使用率を取得
final akashaWeaponUsageRepositoryProvider =
    Provider<AkashaWeaponUsageRepository>((ref) {
      final repo = AkashaWeaponUsageRepository();
      ref.onDispose(repo.dispose);
      return repo;
    });

/// メタランキング（現状は Akasha 武器使用率）
final metaRankingSourceProvider = Provider<MetaRankingSource>((ref) {
  return AkashaWeaponMetaRankingSource(
    ref.watch(akashaWeaponUsageRepositoryProvider),
  );
});

/// キャラ別武器使用率（失敗時は heuristic 空スナップショット）
final weaponUsageRatesProvider =
    FutureProvider.family<WeaponUsageSnapshot, String>((ref, characterId) {
      return ref
          .watch(akashaWeaponUsageRepositoryProvider)
          .getUsageRates(characterId);
    });

/// キャラのスキル詳細 + ステータス計算用データ（失敗時 null）
final avatarDetailProvider = FutureProvider.family<AvatarDetailData?, String>((
  ref,
  characterId,
) {
  return ref.watch(amberDetailRepositoryProvider).getAvatarDetail(characterId);
});

/// 武器のステータス計算用データ（未装備・失敗時 null）
final weaponStatsProvider = FutureProvider.family<WeaponStatsData?, String>((
  ref,
  weaponId,
) {
  if (weaponId.isEmpty) return Future.value(null);
  return ref.watch(amberDetailRepositoryProvider).getWeaponStats(weaponId);
});

/// 武器の詳細（効果・精錬含む。未装備・失敗時 null）
final weaponDetailProvider = FutureProvider.family<WeaponDetailData?, String>((
  ref,
  weaponId,
) {
  if (weaponId.isEmpty) return Future.value(null);
  return ref.watch(amberDetailRepositoryProvider).getWeaponDetail(weaponId);
});

/// 聖遺物セット一覧（セット効果）
final artifactSetsProvider = FutureProvider<List<ArtifactSetDetail>>((ref) {
  return ref.watch(amberDetailRepositoryProvider).getArtifactSets();
});
