import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/master_models.dart';
import '../../domain/bookmark_utils.dart';
import '../../domain/level_config.dart';
import '../../domain/level_progression.dart';
import '../../domain/material_requirements.dart';
import '../../domain/models/bookmark.dart';
import '../../domain/models/calculation_models.dart';
import '../../domain/talent_progression.dart';
import '../../providers/app_providers.dart';
import '../shared/mark_slider.dart';
import '../shared/material_list_tile.dart';

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

  MasterCharacter? _character;
  UserProgress? _progress;
  List<PromoteStage> _promotes = [];
  Map<String, List<TalentLevelUpgrade>> _talents = {};
  Map<String, MasterMaterial> _materials = {};
  List<MaterialBookmarkEntry> _bookmarks = [];
  bool _loading = true;
  String? _error;
  Timer? _saveTimer;

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
      _materials = await ref.read(materialsMapProvider.future);

      _progress = await progressRepo.getOrCreate(
        userId: userId,
        characterId: widget.characterId,
        progressId: const Uuid().v4(),
      );

      final bookmarks = await bookmarkRepo.getAll();
      if (!mounted) return;
      setState(() {
        _level = _progress!.level;
        _talentNormal = _progress!.talentNormal;
        _talentSkill = _progress!.talentSkill;
        _talentBurst = _progress!.talentBurst;
        _weaponLevel = _progress!.weaponLevel;
        _bookmarks = bookmarks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
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

  String _resolveName(String id) => _materials[id]?.name ?? '素材 #$id';

  String? _resolveIcon(String id) => _materials[id]?.iconUrl;

  CultivationBookmarkContext _bookmarkContext(MasterCharacter character) =>
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

  bool _isBookmarked(String sourceKey, String materialId) =>
      isMaterialBookmarked(_bookmarks, sourceKey, materialId);

  @override
  Widget build(BuildContext context) {
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
    );

    final nextStage =
        getNextStageRequirements(_level, _promotes, 'character', 5);
    final talentUpgrades = _talents['skill_0'] ?? [];
    final bookmarkCtx = _bookmarkContext(character);
    final rangeSourceKey =
        makeRangeSourceKey(bookmarkCtx, _level, _targetLevel);

    return Scaffold(
      appBar: AppBar(title: Text(character.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          Text('次の段階', style: Theme.of(context).textTheme.titleLarge),
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
                final sourceKey =
                    makeItemSourceKey(bookmarkCtx, 'next', line.materialId);
                return MaterialListTile(
                  line: line,
                  isBookmarked: _isBookmarked(sourceKey, line.materialId),
                  onToggleBookmark: () => _toggleLineBookmark(
                    bookmarkCtx,
                    line,
                    'next',
                  ),
                );
              },
            ),
          const Divider(height: 32),
          Text('目標までの合計', style: Theme.of(context).textTheme.titleLarge),
          ...rangeLines.map(
            (line) => MaterialListTile(
              line: line,
              isBookmarked: _isBookmarked(rangeSourceKey, line.materialId),
              onToggleBookmark: () => _toggleRangeLineBookmark(
                bookmarkCtx,
                line,
                rangeSourceKey,
              ),
            ),
          ),
          const Divider(height: 32),
          MarkSlider(
            label: '通常攻撃',
            value: _talentNormal,
            marks: talentMarks,
            max: talentLevelMax,
            onChanged: _updateTalentNormal,
          ),
          const SizedBox(height: 8),
          MarkSlider(
            label: '元素スキル',
            value: _talentSkill,
            marks: talentMarks,
            max: talentLevelMax,
            onChanged: _updateTalentSkill,
          ),
          const SizedBox(height: 8),
          MarkSlider(
            label: '元素爆発',
            value: _talentBurst,
            marks: talentMarks,
            max: talentLevelMax,
            onChanged: _updateTalentBurst,
          ),
          if (talentUpgrades.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('天賦 次の段階', style: Theme.of(context).textTheme.titleMedium),
            Builder(
              builder: (context) {
                final next = getNextTalentRequirements(
                  _talentNormal,
                  talentLevelMax,
                  talentUpgrades,
                );
                if (next == null) return const Text('最大レベル');
                final lines = nextStageToRequirementLines(
                  next.materials,
                  const [],
                  next.mora,
                  _resolveName,
                  resolveIcon: _resolveIcon,
                );
                return Column(
                  children: lines
                      .map(
                        (line) => MaterialListTile(
                          line: line,
                          isBookmarked: false,
                          onToggleBookmark: () {},
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
          const Divider(height: 32),
          LevelMarkSlider(
            label: '武器レベル',
            value: _weaponLevel,
            onChanged: _updateWeaponLevel,
          ),
        ],
      ),
    );
  }

  Future<void> _bookmarkRange(
    CultivationBookmarkContext ctx,
    List<RequirementLine> lines,
    String sourceKey,
  ) async {
    final repo = await ref.read(bookmarkRepositoryProvider.future);
    final sourceLabel = makeRangeSourceLabel(ctx, _level, _targetLevel);
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
      final entry = buildBookmarkEntries(
        lines: [line],
        sourceKey: rangeSourceKey,
        sourceLabel: makeRangeSourceLabel(ctx, _level, _targetLevel),
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
