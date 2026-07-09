import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/hoyolab/models/game_record.dart';
import '../../data/artifact_score/artifact_score_weight.dart';
import '../../data/models/master_models.dart';
import '../../domain/bookmark_utils.dart';
import '../../domain/hoyolab_slider_sync.dart';
import '../../domain/level_config.dart';
import '../../domain/level_progression.dart';
import '../../domain/material_requirements.dart';
import '../../domain/artifact_score.dart';
import '../../domain/artifact_score_resolver.dart';
import '../../domain/models/bookmark.dart';
import '../../domain/models/calculation_models.dart';
import '../../domain/hoyolab_relic_sync.dart';
import '../../domain/models/artifact_state.dart';
import '../../providers/app_providers.dart';
import '../../providers/hoyolab_game_providers.dart';
import '../hoyolab/widgets/hoyolab_character_status_card.dart';
import '../shared/game_icon_image.dart';
import '../shared/detail_section_accordion.dart';
import '../shared/mark_slider.dart';
import '../shared/material_list_tile.dart';
import '../shared/max_enhanced_banner.dart';
import 'widgets/character_relics_section.dart';
import 'widgets/talent_materials_section.dart';
import 'widgets/weapon_materials_section.dart';

class CharacterDetailScreen extends ConsumerStatefulWidget {
  const CharacterDetailScreen({super.key, required this.characterId});

  final String characterId;

  @override
  ConsumerState<CharacterDetailScreen> createState() =>
      _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends ConsumerState<CharacterDetailScreen> {
  static const _saveDebounceMs = 800;

  int _level = 1;
  int _targetLevel = levelMax;
  int _talentNormal = 1;
  int _talentSkill = 1;
  int _talentBurst = 1;
  int _weaponLevel = 1;
  int _targetWeaponLevel = levelMax;
  String _weaponId = '';
  String _weaponName = '';
  int _weaponRarity = 4;
  ArtifactState _artifacts = createEmptyArtifactState();

  MasterCharacter? _character;
  UserProgress? _progress;
  List<MasterWeapon> _weapons = [];
  List<PromoteStage> _promotes = [];
  List<PromoteStage> _weaponPromotes = [];
  Map<String, List<TalentLevelUpgrade>> _talents = {};
  Map<String, MasterMaterial> _materials = {};
  List<MaterialBookmarkEntry> _bookmarks = [];
  bool _loading = true;
  String? _error;
  Timer? _saveTimer;
  bool _hoyolabSynced = false;
  DateTime? _lastHoyolabFetchedAt;
  ArtifactScoreType _artifactScoreType = ArtifactScoreType.atk;
  ArtifactScoreType _resolvedArtifactScoreType = ArtifactScoreType.atk;
  ArtifactStatWeights _artifactScoreWeights = scoreWeightsForType(
    ArtifactScoreType.atk,
  );
  bool _artifactScoreTypeUserSet = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final charRepo = await ref.read(characterRepositoryProvider.future);
      final progressRepo = await ref.read(progressRepositoryProvider.future);
      final bookmarkRepo = await ref.read(bookmarkRepositoryProvider.future);
      final userId = await ref.read(localUserIdProvider.future);

      _character = await charRepo.getById(widget.characterId);
      final upgrade = await charRepo.getUpgrade(widget.characterId);
      _promotes = upgrade?.promotes ?? [];
      _talents = upgrade?.talents ?? {};
      _weapons = await charRepo.getAllWeapons();
      _materials = await ref.read(materialsMapProvider.future);

      _progress = await progressRepo.getOrCreate(
        userId: userId,
        characterId: widget.characterId,
        progressId: const Uuid().v4(),
      );

      _weaponId = _progress!.weaponId;
      _weaponName = _progress!.weaponName;
      _weaponLevel = _progress!.weaponLevel;
      await _loadWeaponUpgrade();
      await _loadArtifactScoreSettings();

      final bookmarks = await bookmarkRepo.getAll();
      if (!mounted) return;
      setState(() {
        _level = _progress!.level;
        _talentNormal = _progress!.talentNormal;
        _talentSkill = _progress!.talentSkill;
        _talentBurst = _progress!.talentBurst;
        _artifacts = _progress!.artifacts;
        _bookmarks = bookmarks;
        _loading = false;
      });
      await _syncFromHoyolab();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadWeaponUpgrade() async {
    if (_weaponId.isEmpty) {
      _weaponPromotes = [];
      _weaponRarity = 4;
      return;
    }
    final charRepo = await ref.read(characterRepositoryProvider.future);
    final weapon =
        _weapons.where((w) => w.id == _weaponId).firstOrNull ??
            await charRepo.getWeapon(_weaponId);
    if (weapon != null) {
      _weaponRarity = weapon.rarity;
      _weaponName = weapon.name;
    }
    final weaponUpgrade = await charRepo.getWeaponUpgrade(_weaponId);
    _weaponPromotes = weaponUpgrade?.promotes ?? [];
  }

  Future<void> _syncFromHoyolab() async {
    try {
      final build =
          await ref.read(hoyolabCharacterBuildProvider(widget.characterId).future);
      if (build != null && build.isOwned) {
        await _applyHoyolabBuild(build);
      }
    } catch (_) {
      // HoYoLAB 未連携・取得失敗時はローカル進捗のまま
    }
  }

  Future<void> _applyHoyolabBuildSafe(HoyolabCharacterBuild build) async {
    try {
      await _applyHoyolabBuild(build);
    } catch (_) {
      // HoYoLAB 反映失敗時も詳細画面は表示を継続
    }
  }

  Future<void> _applyHoyolabBuild(HoyolabCharacterBuild build) async {
    if (!build.isOwned || !mounted) return;

    if (_lastHoyolabFetchedAt != null &&
        build.fetchedAt != null &&
        !build.fetchedAt!.isAfter(_lastHoyolabFetchedAt!)) {
      return;
    }

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

    if (snapshot.weaponId != null || snapshot.weaponName != null) {
      await _applyWeaponSnapshot(snapshot);
    }

    if (build.relics.isNotEmpty) {
      _artifacts = mergeRelicsFromHoyolab(
        local: _artifacts,
        relics: build.relics,
      );
    }

    if (!mounted) return;
    setState(() {
      _level = snapshot.level;
      if (build.talents.isNotEmpty) {
        _talentNormal = snapshot.talentNormal;
        _talentSkill = snapshot.talentSkill;
        _talentBurst = snapshot.talentBurst;
      }
      _hoyolabSynced = true;
      _lastHoyolabFetchedAt = build.fetchedAt ?? DateTime.now();
      _progress = _progress?.copyWith(
        level: snapshot.level,
        ascension: snapshot.promoteLevel,
        constellation: snapshot.constellation,
        talentNormal:
            build.talents.isNotEmpty ? snapshot.talentNormal : null,
        talentSkill: build.talents.isNotEmpty ? snapshot.talentSkill : null,
        talentBurst: build.talents.isNotEmpty ? snapshot.talentBurst : null,
        weaponId: _weaponId,
        weaponName: _weaponName,
        weaponLevel: _weaponLevel,
        weaponRefinement:
            snapshot.weaponRefinement ?? _progress?.weaponRefinement ?? 1,
        artifacts: _artifacts,
      );
    });
    _scheduleSave();
  }

  Future<void> _applyWeaponSnapshot(HoyolabSliderSnapshot snapshot) async {
    MasterWeapon? matched;
    if (snapshot.weaponId != null) {
      matched = _weapons.where((w) => w.id == snapshot.weaponId).firstOrNull;
    }
    matched ??= snapshot.weaponName == null
        ? null
        : _weapons.where((w) => w.name == snapshot.weaponName).firstOrNull;

    if (matched != null) {
      _weaponId = matched.id;
      _weaponName = matched.name;
      _weaponRarity = matched.rarity;
    } else if (snapshot.weaponId != null) {
      _weaponId = snapshot.weaponId!;
      _weaponName = snapshot.weaponName ?? '';
    }
    if (snapshot.weaponLevel != null) {
      _weaponLevel = snapshot.weaponLevel!;
    }
    await _loadWeaponUpgrade();
  }

  Future<void> _loadArtifactScoreSettings() async {
    final character = _character;
    if (character == null) return;

    final userScoreType =
        userArtifactScoreTypeFromStorage(_progress!.artifactScoreType);
    _artifactScoreTypeUserSet = userScoreType != null;

    final resolver = ArtifactScoreResolver(
      ref.read(artifactScoreWeightRepositoryProvider),
    );
    final autoSettings = await resolver.resolve(character: character);
    _resolvedArtifactScoreType = autoSettings.scoreType;

    final settings = await resolver.resolve(
      character: character,
      userScoreType: userScoreType,
      userScoreTypeIsSet: _artifactScoreTypeUserSet,
    );

    _artifactScoreType = settings.scoreType;
    _artifactScoreWeights = settings.weights;
  }

  void _scheduleSave() {
    final base = _progress;
    if (base == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: _saveDebounceMs),
      () => _persistProgress(base),
    );
  }

  Future<void> _persistProgress(UserProgress base) async {
    final updated = base.copyWith(
      level: _level,
      talentNormal: _talentNormal,
      talentSkill: _talentSkill,
      talentBurst: _talentBurst,
      weaponLevel: _weaponLevel,
      weaponId: _weaponId,
      weaponName: _weaponName,
      artifacts: _artifacts,
    );
    _progress = updated;
    try {
      final repo = await ref.read(progressRepositoryProvider.future);
      await repo.save(updated);
    } catch (_) {
      // 保存失敗は UI を落とさない
    }
  }

  void _updateLevel(int v) {
    setState(() => _level = v);
    _scheduleSave();
  }

  void _updateTalentNormal(int v) {
    setState(() => _talentNormal = v);
    _scheduleSave();
  }

  void _updateTalentSkill(int v) {
    setState(() => _talentSkill = v);
    _scheduleSave();
  }

  void _updateTalentBurst(int v) {
    setState(() => _talentBurst = v);
    _scheduleSave();
  }

  void _updateWeaponLevel(int v) {
    setState(() => _weaponLevel = v);
    _scheduleSave();
  }

  void _updateArtifacts(ArtifactState artifacts) {
    setState(() => _artifacts = artifacts);
    _scheduleSave();
  }

  void _updateArtifactScoreType(ArtifactScoreType type) {
    setState(() {
      _artifactScoreType = type;
      _artifactScoreWeights = scoreWeightsForType(type);
      _artifactScoreTypeUserSet = true;
    });
    _persistArtifactScoreType();
    _scheduleSave();
  }

  Future<void> _persistArtifactScoreType() async {
    final base = _progress;
    if (base == null) return;

    final updated = base.copyWith(
      artifactScoreType: _artifactScoreTypeUserSet
          ? artifactScoreTypeToUserStorage(_artifactScoreType)
          : '',
    );
    _progress = updated;
    try {
      final repo = await ref.read(progressRepositoryProvider.future);
      await repo.save(updated);
    } catch (_) {
      // 保存失敗は UI を落とさない
    }
  }

  Future<void> _onWeaponSelected(String? weaponId) async {
    if (weaponId == null || weaponId.isEmpty) {
      setState(() {
        _weaponId = '';
        _weaponName = '';
        _weaponPromotes = [];
        _weaponRarity = 4;
      });
    } else {
      final w = _weapons.where((x) => x.id == weaponId).firstOrNull;
      setState(() {
        _weaponId = weaponId;
        _weaponName = w?.name ?? '';
        _weaponRarity = w?.rarity ?? 4;
      });
      await _loadWeaponUpgrade();
      if (mounted) setState(() {});
    }
    _scheduleSave();
  }

  String _resolveName(String id) => _materials[id]?.name ?? '素材 #$id';

  String? _resolveIcon(String id) => _materials[id]?.iconUrl;

  CultivationBookmarkContext _characterBookmarkContext(
    MasterCharacter character,
  ) =>
      CultivationBookmarkContext(
        kind: CultivationKind.characterLevel,
        targetId: character.id,
        targetName: character.name,
        character: BookmarkCharacterSource(
          characterId: character.id,
          characterName: character.name,
          characterIconUrl: character.iconUrl,
        ),
      );

  CultivationBookmarkContext _weaponBookmarkContext(MasterCharacter character) =>
      CultivationBookmarkContext(
        kind: CultivationKind.weaponLevel,
        targetId: _weaponId.isEmpty ? character.id : _weaponId,
        targetName: _weaponName.isEmpty ? character.name : _weaponName,
        character: BookmarkCharacterSource(
          characterId: character.id,
          characterName: character.name,
          characterIconUrl: character.iconUrl,
        ),
      );

  bool _isBookmarked(String sourceKey, String materialId) =>
      isMaterialBookmarked(_bookmarks, sourceKey, materialId);

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<HoyolabCharacterBuild?>>(
      hoyolabCharacterBuildProvider(widget.characterId),
      (prev, next) {
        next.whenData((build) {
          if (build != null && build.isOwned && !_loading) {
            unawaited(_applyHoyolabBuildSafe(build));
          }
        });
      },
    );

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text('エラー: $_error')));
    }

    final character = _character;
    if (character == null) {
      return const Scaffold(body: Center(child: Text('キャラが見つかりません')));
    }

    final rangeLines = getRangeLevelRequirements(
      _level,
      _targetLevel,
      _promotes,
      'character',
      resolveName: _resolveName,
      resolveIcon: _resolveIcon,
    );

    final nextStage =
        getNextStageRequirements(_level, _promotes, 'character', 5);
    final bookmarkCtx = _characterBookmarkContext(character);
    final weaponBookmarkCtx = _weaponBookmarkContext(character);
    final rangeSourceKey =
        makeRangeSourceKey(bookmarkCtx, _level, _targetLevel);

    final hoyolabBuild = ref.watch(hoyolabCharacterBuildProvider(widget.characterId)).valueOrNull;
    final talentSummary = _buildTalentSummary();
    final hoyolabSummary = _buildHoyolabSummary(hoyolabBuild);
    final artifactScoreType = _artifactScoreType;
    final resolvedArtifactScoreType = _resolvedArtifactScoreType;

    return Scaffold(
      appBar: AppBar(title: Text(character.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DetailSectionAccordion(
            title: 'キャラレベル',
            summary: Text(
              _level >= levelMax
                  ? '最大強化済み · Lv.$_level'
                  : 'Lv.$_level → 目標 Lv.$_targetLevel',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_hoyolabSynced) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      avatar: Icon(
                        Icons.sync,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      label: const Text('HoYoLAB のレベルを反映済み'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_level >= levelMax) ...[
                  MaxEnhancedBanner(label: 'キャラクターレベル', level: _level),
                ] else ...[
                  LevelMarkSlider(
                    label: '現在レベル',
                    value: _level,
                    onChanged: _updateLevel,
                  ),
                  const SizedBox(height: 16),
                  LevelMarkSlider(
                    label: '目標レベル',
                    value: _targetLevel,
                    onChanged: (v) => setState(() => _targetLevel = v),
                    headerTrailing: IconButton(
                      icon: const Icon(Icons.bookmark_add_outlined),
                      tooltip: '範囲をブックマーク',
                      onPressed: () => _bookmarkRange(
                        bookmarkCtx,
                        rangeLines,
                        rangeSourceKey,
                      ),
                    ),
                  ),
                  const Divider(height: 32),
                  Text('次の段階', style: Theme.of(context).textTheme.titleMedium),
                  if (nextStage == null)
                    const Text('最大レベルです')
                  else
                    ...nextStageToRequirementLines(
                      nextStage.materials,
                      nextStage.levelUpMaterials,
                      nextStage.mora,
                      _resolveName,
                      resolveIcon: _resolveIcon,
                    ).map(
                      (line) {
                        final sourceKey = makeItemSourceKey(
                          bookmarkCtx,
                          'next',
                          line.materialId,
                        );
                        return MaterialListTile(
                          line: line,
                          isBookmarked:
                              _isBookmarked(sourceKey, line.materialId),
                          onToggleBookmark: () => _toggleLineBookmark(
                            bookmarkCtx,
                            line,
                            'next',
                          ),
                        );
                      },
                    ),
                  const Divider(height: 24),
                  Text('目標までの合計',
                      style: Theme.of(context).textTheme.titleMedium),
                  ...rangeLines.map(
                    (line) => MaterialListTile(
                      line: line,
                      isBookmarked:
                          _isBookmarked(rangeSourceKey, line.materialId),
                      onToggleBookmark: () => _toggleRangeLineBookmark(
                        bookmarkCtx,
                        line,
                        rangeSourceKey,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          DetailSectionAccordion(
            title: '武器',
            summary: _buildWeaponSummaryWidget(),
            child: WeaponMaterialsSection(
              showTitle: false,
              weapons: _weapons,
              selectedWeaponId: _weaponId,
              weaponLevel: _weaponLevel,
              targetWeaponLevel: _targetWeaponLevel,
              promotes: _weaponPromotes,
              weaponRarity: _weaponRarity,
              bookmarkContext: weaponBookmarkCtx,
              bookmarks: _bookmarks,
              resolveName: _resolveName,
              resolveIcon: _resolveIcon,
              onWeaponSelected: _onWeaponSelected,
              onWeaponLevelChanged: _updateWeaponLevel,
              onTargetWeaponLevelChanged: (v) =>
                  setState(() => _targetWeaponLevel = v),
              onToggleBookmark: (line, scope) => _toggleLineBookmark(
                weaponBookmarkCtx,
                line,
                scope,
              ),
              onToggleRangeBookmark: (line, rangeSourceKey) =>
                  _toggleRangeLineBookmark(
                weaponBookmarkCtx,
                line,
                rangeSourceKey,
              ),
              onBookmarkRange: (lines, sourceKey) => _bookmarkRange(
                weaponBookmarkCtx,
                lines,
                sourceKey,
              ),
            ),
          ),
          const SizedBox(height: 12),
          DetailSectionAccordion(
            title: '聖遺物',
            summary: ArtifactSummaryContent(
              artifacts: _artifacts,
              scoreType: artifactScoreType,
              resolvedScoreType: resolvedArtifactScoreType,
              scoreTypeUserSet: _artifactScoreTypeUserSet,
              weights: _artifactScoreWeights,
            ),
            child: CharacterRelicsSection(
              artifacts: _artifacts,
              scoreType: artifactScoreType,
              resolvedScoreType: resolvedArtifactScoreType,
              scoreTypeUserSet: _artifactScoreTypeUserSet,
              weights: _artifactScoreWeights,
              onScoreTypeChanged: _updateArtifactScoreType,
              onChanged: _updateArtifacts,
            ),
          ),
          const SizedBox(height: 12),
          DetailSectionAccordion(
            title: 'スキル天賦',
            summary: Text(talentSummary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildTalentSections(character),
            ),
          ),
          const SizedBox(height: 12),
          DetailSectionAccordion(
            title: 'HoYoLAB 実データ',
            summary: Text(hoyolabSummary),
            child: HoyolabCharacterStatusCard(characterId: widget.characterId),
          ),
        ],
      ),
    );
  }

  Widget _buildWeaponSummaryWidget() {
    if (_weaponId.isEmpty && _weaponName.isEmpty) {
      return const Text('武器未選択');
    }
    final weapon = _weapons.where((w) => w.id == _weaponId).firstOrNull;
    final name = _weaponName.isEmpty ? '武器' : _weaponName;
    final levelText = _weaponLevel >= levelMax
        ? '最大強化済み Lv.$_weaponLevel'
        : 'Lv.$_weaponLevel → 目標 Lv.$_targetWeaponLevel';

    return Row(
      children: [
        GameIconImage(iconUrl: weapon?.iconUrl, size: 32),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$name · $levelText'),
        ),
      ],
    );
  }

  String _buildTalentSummary() {
    final allMax = _talentNormal >= talentLevelMax &&
        _talentSkill >= talentLevelMax &&
        _talentBurst >= talentLevelMax;
    if (allMax) {
      return '最大強化済み · 通常$_talentNormal / スキル$_talentSkill / 爆発$_talentBurst';
    }
    return '通常$_talentNormal / スキル$_talentSkill / 爆発$_talentBurst';
  }

  String _buildHoyolabSummary(HoyolabCharacterBuild? build) {
    if (build == null || !build.isOwned) {
      return '未連携または未所持';
    }
    final parts = <String>['Lv.${build.level}'];
    if (build.constellation > 0) {
      parts.add('凸${build.constellation}');
    }
    if (build.weapon != null && build.weapon!.name.isNotEmpty) {
      parts.add(build.weapon!.name);
    }
    return parts.join(' · ');
  }

  List<Widget> _buildTalentSections(MasterCharacter character) {
    const slots = [
      ('normal', 'skill_0', '通常攻撃', _TalentSlot.normal),
      ('skill', 'skill_1', '元素スキル', _TalentSlot.skill),
      ('burst', 'skill_2', '元素爆発', _TalentSlot.burst),
    ];

    return slots.map((slot) {
      final upgrades = _talents[slot.$2] ?? [];
      if (upgrades.isEmpty) return const SizedBox.shrink();
      final level = switch (slot.$4) {
        _TalentSlot.normal => _talentNormal,
        _TalentSlot.skill => _talentSkill,
        _TalentSlot.burst => _talentBurst,
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TalentMaterialsSection(
          characterId: character.id,
          characterName: character.name,
          characterIconUrl: character.iconUrl,
          talentKind: slot.$1,
          talentKey: slot.$2,
          label: slot.$3,
          currentLevel: level,
          upgrades: upgrades,
          bookmarks: _bookmarks,
          resolveName: _resolveName,
          resolveIcon: _resolveIcon,
          onLevelChanged: switch (slot.$4) {
            _TalentSlot.normal => _updateTalentNormal,
            _TalentSlot.skill => _updateTalentSkill,
            _TalentSlot.burst => _updateTalentBurst,
          },
          onToggleBookmark: _toggleLineBookmark,
          onBookmarkRange: _bookmarkRange,
          onToggleRangeLineBookmark: _toggleRangeLineBookmark,
        ),
      );
    }).toList();
  }

  Future<void> _bookmarkRange(
    CultivationBookmarkContext ctx,
    List<RequirementLine> lines,
    String sourceKey,
  ) async {
    final repo = await ref.read(bookmarkRepositoryProvider.future);
    final from = ctx.kind == CultivationKind.weaponLevel
        ? _weaponLevel
        : _level;
    final to = ctx.kind == CultivationKind.weaponLevel
        ? _targetWeaponLevel
        : _targetLevel;
    final sourceLabel = makeRangeSourceLabel(ctx, from, to);
    final iconMap = {
      for (final m in _materials.values) m.id: m.iconUrl,
    };
    final entries = buildBookmarkEntries(
      lines: lines,
      sourceKey: sourceKey,
      sourceLabel: sourceLabel,
      character: ctx.character,
      iconUrlByMaterialId: iconMap,
    );
    await repo.replaceSourceBookmarks(
      sourceKey: sourceKey,
      entries: entries,
    );
    _bookmarks = await repo.getAll();
    ref.invalidate(aggregatedBookmarksProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ブックマークに追加しました')),
      );
    }
    setState(() {});
  }

  Future<void> _toggleRangeLineBookmark(
    CultivationBookmarkContext ctx,
    RequirementLine line,
    String rangeSourceKey,
  ) async {
    final repo = await ref.read(bookmarkRepositoryProvider.future);
    final id = makeBookmarkId(rangeSourceKey, line.materialId);
    if (_isBookmarked(rangeSourceKey, line.materialId)) {
      await repo.remove(id);
      _bookmarks.removeWhere((b) => b.id == id);
    } else {
      final iconMap = {
        for (final m in _materials.values) m.id: m.iconUrl,
      };
      final from = ctx.kind == CultivationKind.weaponLevel
          ? _weaponLevel
          : _level;
      final to = ctx.kind == CultivationKind.weaponLevel
          ? _targetWeaponLevel
          : _targetLevel;
      final entry = buildBookmarkEntries(
        lines: [line],
        sourceKey: rangeSourceKey,
        sourceLabel: makeRangeSourceLabel(ctx, from, to),
        character: ctx.character,
        iconUrlByMaterialId: iconMap,
      ).first;
      await repo.addOrUpdate(entry);
      _bookmarks.add(entry);
    }
    ref.invalidate(aggregatedBookmarksProvider);
    setState(() {});
  }

  Future<void> _toggleLineBookmark(
    CultivationBookmarkContext ctx,
    RequirementLine line,
    String scope,
  ) async {
    final repo = await ref.read(bookmarkRepositoryProvider.future);
    final sourceKey = makeItemSourceKey(ctx, scope, line.materialId);
    final id = makeBookmarkId(sourceKey, line.materialId);
    if (_isBookmarked(sourceKey, line.materialId)) {
      await repo.remove(id);
      _bookmarks.removeWhere((b) => b.id == id);
    } else {
      final iconMap = {
        for (final m in _materials.values) m.id: m.iconUrl,
      };
      final entry = buildBookmarkEntries(
        lines: [line],
        sourceKey: sourceKey,
        sourceLabel: makeItemSourceLabel(ctx, line.name),
        character: ctx.character,
        iconUrlByMaterialId: iconMap,
      ).first;
      await repo.addOrUpdate(entry);
      _bookmarks.add(entry);
    }
    ref.invalidate(aggregatedBookmarksProvider);
    setState(() {});
  }
}

enum _TalentSlot { normal, skill, burst }
