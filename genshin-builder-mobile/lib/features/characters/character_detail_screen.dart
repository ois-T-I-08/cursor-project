import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/bookmark_utils.dart';
import '../../core/errors/user_facing_error.dart';
import '../../domain/level_progression.dart';
import '../../domain/material_requirements.dart';
import '../../domain/models/bookmark.dart';
import '../../domain/models/master_models.dart';
import '../../providers/app_providers.dart';
import '../../providers/character_detail_providers.dart';
import '../../providers/hoyolab_game_providers.dart';
import '../../providers/growth_providers.dart';
import '../../providers/hoyolab_providers.dart' show featureFlagsProvider;
import '../../domain/recommendation/recommendation.dart';
import '../../domain/planning/investment_diagnosis.dart';
import '../shared/shell_menu_button.dart';
import 'character_detail_state.dart';
import 'widgets/character_detail_bookmark_actions.dart';
import 'widgets/character_detail_header.dart';
import 'widgets/character_detail_tab_views.dart';
import 'widgets/weapon_change_confirm_dialog.dart';

class CharacterDetailScreen extends ConsumerStatefulWidget {
  const CharacterDetailScreen({super.key, required this.characterId});

  final String characterId;

  @override
  ConsumerState<CharacterDetailScreen> createState() =>
      _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends ConsumerState<CharacterDetailScreen>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 6;

  late TabController _tabController;
  List<MaterialBookmarkEntry> _bookmarks = [];
  late final CharacterDetailBookmarkActions _bookmarkActions;
  bool _bookmarksLoaded = false;

  CharacterDetailNotifier get _notifier =>
      ref.read(characterDetailProvider(widget.characterId).notifier);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _bookmarkActions = CharacterDetailBookmarkActions(
      ref: ref,
      getContext: () => context,
      getBookmarks: () => _bookmarks,
      setBookmarks: (bookmarks) => _bookmarks = bookmarks,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      getMaterials: () =>
          ref.read(characterDetailProvider(widget.characterId)).materials,
      getLevel: () =>
          ref.read(characterDetailProvider(widget.characterId)).level,
      getTargetLevel: () =>
          ref.read(characterDetailProvider(widget.characterId)).targetLevel,
      getWeaponLevel: () =>
          ref.read(characterDetailProvider(widget.characterId)).weaponLevel,
      getTargetWeaponLevel: () => ref
          .read(characterDetailProvider(widget.characterId))
          .targetWeaponLevel,
    );
    unawaited(_loadBookmarks());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBookmarks() async {
    try {
      final bookmarkRepo = await ref.read(bookmarkRepositoryProvider.future);
      final bookmarks = await bookmarkRepo.getAll();
      if (!mounted) return;
      setState(() {
        _bookmarks = bookmarks;
        _bookmarksLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _bookmarksLoaded = true);
    }
  }

  Future<void> _confirmResetToFetched(CharacterDetailState detail) async {
    if (detail.fetchedSnapshot == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取得情報に戻す'),
        content: const Text(
          'レベル・天賦・武器・聖遺物の手動変更をすべて破棄し、'
          '取得時の状態に戻します。よろしいですか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('戻す'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _notifier.resetToFetched();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('取得情報に戻しました')),
    );
  }

  Future<void> _onWeaponSelected(
    CharacterDetailState detail,
    String? weaponId,
  ) async {
    if (weaponId == detail.weaponId) return;
    if (weaponId == null || weaponId.isEmpty) {
      _notifier.clearWeapon();
      return;
    }

    final character = detail.character;
    final newWeapon = detail.weapons.where((x) => x.id == weaponId).firstOrNull;

    // 変更前後のステータス差分を提示して確認を取る
    if (character != null && newWeapon != null && mounted) {
      final currentWeapon =
          detail.weapons.where((x) => x.id == detail.weaponId).firstOrNull;
      final confirmed = await showWeaponChangeConfirmDialog(
        context: context,
        ref: ref,
        character: character,
        promotes: detail.promotes,
        currentBuild: detail.snapshotFromCurrent(),
        currentWeapon: currentWeapon,
        newWeapon: newWeapon,
      );
      if (confirmed != true) {
        // キャンセル: ドロップダウン表示を現在値へ戻す
        if (mounted) setState(() {});
        return;
      }
    }
    if (!mounted) return;

    await _notifier.applyWeaponSelection(weaponId);
  }

  String _resolveName(CharacterDetailState detail, String id) =>
      detail.materials[id]?.name ?? '素材 #$id';

  String? _resolveIcon(CharacterDetailState detail, String id) =>
      detail.materials[id]?.iconUrl;

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

  CultivationBookmarkContext _weaponBookmarkContext(
    MasterCharacter character,
    CharacterDetailState detail,
  ) =>
      CultivationBookmarkContext(
        kind: CultivationKind.weaponLevel,
        targetId: detail.weaponId.isEmpty ? character.id : detail.weaponId,
        targetName:
            detail.weaponName.isEmpty ? character.name : detail.weaponName,
        character: BookmarkCharacterSource(
          characterId: character.id,
          characterName: character.name,
          characterIconUrl: character.iconUrl,
        ),
      );

  bool _isBookmarked(String sourceKey, String materialId) =>
      _bookmarkActions.isBookmarked(sourceKey, materialId);

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(characterDetailProvider(widget.characterId));
    final notifier = _notifier;

    ref.listen(hoyolabCharacterBuildProvider(widget.characterId), (prev, next) {
      next.whenData((build) {
        final current =
            ref.read(characterDetailProvider(widget.characterId));
        if (build != null && build.isOwned && !current.loading) {
          unawaited(notifier.applyHoyolabBuildSafe(build));
        }
      });
    });

    if (detail.loading || !_bookmarksLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (detail.error != null) {
      return Scaffold(
        body: Center(child: Text(userFacingError(detail.error))),
      );    }

    final character = detail.character;
    if (character == null) {
      return const Scaffold(body: Center(child: Text('キャラが見つかりません')));
    }

    final rangeLines = getRangeLevelRequirements(
      detail.level,
      detail.targetLevel,
      detail.promotes,
      'character',
      resolveName: (id) => _resolveName(detail, id),
      resolveIcon: (id) => _resolveIcon(detail, id),
    );

    final nextStage = getNextStageRequirements(
      detail.level,
      detail.promotes,
      'character',
      5,
    );
    final bookmarkCtx = _characterBookmarkContext(character);
    final weaponBookmarkCtx = _weaponBookmarkContext(character, detail);
    final rangeSourceKey =
        makeRangeSourceKey(bookmarkCtx, detail.level, detail.targetLevel);

    return Scaffold(
      appBar: AppBar(
        title: const Text('キャラ詳細'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_backup_restore),
            tooltip: '取得情報に戻す',
            onPressed: detail.fetchedSnapshot == null
                ? null
                : () => unawaited(_confirmResetToFetched(detail)),
          ),
          const ShellMenuButton(),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CharacterDetailHeader(
            character: character,
            level: detail.level,
            constellation: detail.constellation,
            onConstellationChanged: notifier.updateConstellation,
          ),
          _DiagnosisCard(characterId: widget.characterId),
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'レベル'),
                Tab(text: '武器'),
                Tab(text: '聖遺物'),
                Tab(text: '天賦'),
                Tab(text: '想定'),
                Tab(text: 'HoYoLAB'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: CharacterDetailTabViews(
                characterId: widget.characterId,
                character: character,
                hoyolabSynced: detail.hoyolabSynced,
                level: detail.level,
                targetLevel: detail.targetLevel,
                talentNormal: detail.talentNormal,
                talentSkill: detail.talentSkill,
                talentBurst: detail.talentBurst,
                weaponId: detail.weaponId,
                weaponLevel: detail.weaponLevel,
                targetWeaponLevel: detail.targetWeaponLevel,
                weaponRarity: detail.weaponRarity,
                weaponRefinement: detail.progress?.weaponRefinement ?? 1,
                artifacts: detail.artifacts,
                promotes: detail.promotes,
                weaponPromotes: detail.weaponPromotes,
                talents: detail.talents,
                weapons: detail.weapons,
                bookmarks: _bookmarks,
                fetchedSnapshot: detail.fetchedSnapshot,
                artifactScoreType: detail.artifactScoreType,
                resolvedArtifactScoreType: detail.resolvedArtifactScoreType,
                artifactScoreWeights: detail.artifactScoreWeights,
                artifactScoreTypeUserSet: detail.artifactScoreTypeUserSet,
                artifactCompleted: detail.artifactCompleted,
                bookmarkCtx: bookmarkCtx,
                weaponBookmarkCtx: weaponBookmarkCtx,
                rangeLines: rangeLines,
                rangeSourceKey: rangeSourceKey,
                nextStage: nextStage,
                bookmarkActions: _bookmarkActions,
                resolveName: (id) => _resolveName(detail, id),
                resolveIcon: (id) => _resolveIcon(detail, id),
                isBookmarked: _isBookmarked,
                onLevelChanged: notifier.updateLevel,
                onTargetLevelChanged: notifier.updateTargetLevel,
                onTalentNormalChanged: notifier.updateTalentNormal,
                onTalentSkillChanged: notifier.updateTalentSkill,
                onTalentBurstChanged: notifier.updateTalentBurst,
                onWeaponSelected: (id) => _onWeaponSelected(detail, id),
                onWeaponLevelChanged: notifier.updateWeaponLevel,
                onTargetWeaponLevelChanged: notifier.updateTargetWeaponLevel,
                onArtifactsChanged: notifier.updateArtifacts,
                onArtifactScoreTypeChanged: notifier.updateArtifactScoreType,
                onArtifactCompletedChanged: notifier.updateArtifactCompleted,
                onResetToFetched: () =>
                    unawaited(_confirmResetToFetched(detail)),
                snapshotFromCurrent: detail.snapshotFromCurrent,
              ).buildTabs(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosisCard extends ConsumerWidget {
  const _DiagnosisCard({required this.characterId});
  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flagsAsync = ref.watch(featureFlagsProvider);
    return flagsAsync.maybeWhen(
      data: (flags) => flags.enableInvestmentDiagnosis
          ? _DiagnosisContent(characterId: characterId)
          : const SizedBox.shrink(),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _DiagnosisContent extends ConsumerWidget {
  const _DiagnosisContent({required this.characterId});
  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagAsync = ref.watch(characterDiagnosisProvider(characterId));
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: diagAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
        data: (diag) {
          if (diag.topFindings.isEmpty) return const SizedBox.shrink();
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('\u80b2\u6210\u8a3a\u65ad', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  ...diag.topFindings.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              f.severity == DiagnosisSeverity.warning
                                  ? Icons.warning_amber
                                  : Icons.info_outline,
                              size: 18,
                              color: f.severity == DiagnosisSeverity.warning
                                  ? Colors.orange
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f.title, style: theme.textTheme.bodyMedium),
                                  if (f.explanation.isNotEmpty)
                                    Text(f.explanation, style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    )),
                                  if (f.recommendation != null && f.recommendation!.isNotEmpty)
                                    Text(f.recommendation!,
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.primary,
                                        )),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
                  Text(
                    '\u4fe1\u983c\u5ea6: ${_confidenceLabel(diag.topFindings.firstOrNull?.confidence ?? RecommendationConfidence.unknown)}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _confidenceLabel(RecommendationConfidence c) {
    switch (c) {
      case RecommendationConfidence.high: return '\u9ad8';
      case RecommendationConfidence.medium: return '\u4e2d';
      case RecommendationConfidence.low: return '\u4f4e';
      case RecommendationConfidence.unknown: return '\u4e0d\u660e';
    }
  }
}
