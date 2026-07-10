import 'package:uuid/uuid.dart';

import '../../domain/daily_materials/daily_material_models.dart';
import '../../domain/daily_materials/daily_progress_prefetch.dart';
import '../../domain/hoyolab_slider_sync.dart';
import '../hoyolab/hoyolab_game_data_repository.dart';
import '../hoyolab/models/game_record.dart';
import '../repositories/character_repository.dart';
import '../repositories/progress_repository.dart';
import 'daily_material_schedule_repository.dart';

class DailyProgressPrefetchResult {
  const DailyProgressPrefetchResult({
    required this.weekday,
    required this.targetCharacterIds,
    required this.createdOrEnsured,
    required this.syncedFromHoyolab,
    required this.skippedNotLinked,
    this.errors = const [],
  });

  final int weekday;
  final List<String> targetCharacterIds;
  final int createdOrEnsured;
  final int syncedFromHoyolab;
  final bool skippedNotLinked;
  final List<String> errors;
}

/// 今日の曜日素材を使う所持キャラだけ Progress を用意し、HoYoLAB 詳細を裏同期する
class DailyProgressPrefetchService {
  DailyProgressPrefetchService({
    required DailyMaterialScheduleRepository scheduleRepository,
    required CharacterRepository characterRepository,
    required ProgressRepository progressRepository,
    required HoyolabGameDataRepository hoyolabRepository,
    this.concurrency = 3,
  })  : _scheduleRepository = scheduleRepository,
        _characterRepository = characterRepository,
        _progressRepository = progressRepository,
        _hoyolabRepository = hoyolabRepository;

  final DailyMaterialScheduleRepository _scheduleRepository;
  final CharacterRepository _characterRepository;
  final ProgressRepository _progressRepository;
  final HoyolabGameDataRepository _hoyolabRepository;
  final int concurrency;
  final _uuid = const Uuid();

  Future<DailyProgressPrefetchResult> prefetchForToday({
    required String userId,
    Set<String> ownedCharacterIds = const {},
    int? weekday,
    bool syncHoyolabDetails = true,
  }) async {
    final day = weekday ?? genshinIsoWeekday();
    final schedule = await _scheduleRepository.getSchedule();
    final upgrades = await _characterRepository.getAllUpgrades();

    final needing = characterIdsNeedingTalentMaterialsOnDay(
      schedule: schedule,
      weekday: day,
      talentsByCharacterId: {
        for (final e in upgrades.entries) e.key: e.value.talents,
      },
    );

    // HoYoLAB 連携時は所持キャラに限定（未所持に初期 Progress を作らない）
    final targets = ownedCharacterIds.isEmpty
        ? <String>{}
        : needing.intersection(ownedCharacterIds);

    if (targets.isEmpty) {
      return DailyProgressPrefetchResult(
        weekday: day,
        targetCharacterIds: const [],
        createdOrEnsured: 0,
        syncedFromHoyolab: 0,
        skippedNotLinked: ownedCharacterIds.isEmpty,
      );
    }

    var ensured = 0;
    for (final characterId in targets) {
      await _progressRepository.getOrCreate(
        userId: userId,
        characterId: characterId,
        progressId: _uuid.v4(),
      );
      ensured++;
    }

    if (!syncHoyolabDetails) {
      return DailyProgressPrefetchResult(
        weekday: day,
        targetCharacterIds: targets.toList()..sort(),
        createdOrEnsured: ensured,
        syncedFromHoyolab: 0,
        skippedNotLinked: false,
      );
    }

    var synced = 0;
    final errors = <String>[];
    final list = targets.toList()..sort();
    for (var i = 0; i < list.length; i += concurrency) {
      final chunk = list.sublist(
        i,
        (i + concurrency).clamp(0, list.length),
      );
      await Future.wait(
        chunk.map((id) async {
          try {
            final build = await _hoyolabRepository.fetchCharacterBuild(id);
            if (build == null || !build.isOwned) return;
            final ok = await _applyBuild(userId: userId, build: build);
            if (ok) synced++;
          } catch (e) {
            errors.add('$id: $e');
          }
        }),
      );
    }

    return DailyProgressPrefetchResult(
      weekday: day,
      targetCharacterIds: list,
      createdOrEnsured: ensured,
      syncedFromHoyolab: synced,
      skippedNotLinked: false,
      errors: errors,
    );
  }

  Future<bool> _applyBuild({
    required String userId,
    required HoyolabCharacterBuild build,
  }) async {
    final existing = await _progressRepository.getOrCreate(
      userId: userId,
      characterId: build.id,
      progressId: _uuid.v4(),
    );

    final snapshot = buildHoyolabSliderSnapshot(
      level: build.level,
      promoteLevel: build.promoteLevel,
      constellation: build.constellation,
      talents: build.talents
          .map((t) => HoyolabTalentInput(name: t.name, level: t.level))
          .toList(),
      weaponId: build.weapon?.id,
      weaponName: build.weapon?.name,
      weaponLevel: build.weapon?.level,
      weaponRefinement: build.weapon?.refinement,
    );

    final updated = existing.copyWith(
      level: snapshot.level,
      ascension: snapshot.promoteLevel,
      constellation: snapshot.constellation,
      talentNormal:
          build.talents.isNotEmpty ? snapshot.talentNormal : null,
      talentSkill: build.talents.isNotEmpty ? snapshot.talentSkill : null,
      talentBurst: build.talents.isNotEmpty ? snapshot.talentBurst : null,
      weaponId: snapshot.weaponId ?? existing.weaponId,
      weaponName: snapshot.weaponName ?? existing.weaponName,
      weaponLevel: snapshot.weaponLevel ?? existing.weaponLevel,
      weaponRefinement:
          snapshot.weaponRefinement ?? existing.weaponRefinement,
    );
    await _progressRepository.save(updated);
    return build.talents.isNotEmpty || snapshot.weaponId != null;
  }
}
