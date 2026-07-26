import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/master_models.dart';
import '../../domain/team_recommendation/team_template_replacement.dart';
import '../../providers/app_providers.dart';
import '../../providers/team_recommendation_providers.dart';
import '../shared/game_icon_image.dart';

class PublishedTeamTemplatesSection extends ConsumerWidget {
  const PublishedTeamTemplatesSection({
    required this.attackerId,
    this.onApplyTeam,
    super.key,
  });

  final String attackerId;
  final ValueChanged<List<TeamTemplateMember>>? onApplyTeam;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names =
        ref.watch(charactersProvider).valueOrNull ?? const <MasterCharacter>[];
    final byId = {for (final character in names) character.id: character};
    return ref
        .watch(teamTemplatesProvider)
        .when(
          loading:
              () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
          error:
              (_, __) => Row(
                children: [
                  const Expanded(child: Text('承認済み編成テンプレートを取得できませんでした。')),
                  IconButton(
                    onPressed: () => ref.invalidate(teamTemplatesProvider),
                    tooltip: '再試行',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
          data: (templates) {
            final relevant =
                templates
                    .where(
                      (template) => template.members.any(
                        (member) => member.characterId == attackerId,
                      ),
                    )
                    .toList();
            if (relevant.isEmpty) {
              return const Text('このキャラを含む承認済み編成テンプレートはまだありません。');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final template in relevant)
                  _TemplateCard(
                    template: template,
                    characters: byId,
                    onApplyTeam: onApplyTeam,
                  ),
              ],
            );
          },
        );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.characters,
    required this.onApplyTeam,
  });

  final PublishedTeamTemplate template;
  final Map<String, MasterCharacter> characters;
  final ValueChanged<List<TeamTemplateMember>>? onApplyTeam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(template.name, style: theme.textTheme.titleSmall),
            if (template.archetype.isNotEmpty)
              Text(template.archetype, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final member in template.members)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: GameIconImage(
                  iconUrl: characters[member.characterId]?.iconUrl ?? '',
                  size: 36,
                  borderRadius: 8,
                  fallback: Text(
                    _characterName(characters, member.characterId)[0],
                  ),
                ),
                title: Text(_characterName(characters, member.characterId)),
                subtitle: Text(_roleLabel(member.role)),
                trailing: TextButton(
                  onPressed:
                      () => _openCandidates(
                        context,
                        template: template,
                        member: member,
                        characters: characters,
                        onApplyTeam: onApplyTeam,
                      ),
                  child: const Text('入れ替え候補'),
                ),
              ),
            Text(
              '出典: ${_sourceLabel(template.source)}／更新: '
              '${template.updatedAt.toLocal().toString().split(' ').first}',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openCandidates(
  BuildContext context, {
  required PublishedTeamTemplate template,
  required TeamTemplateMember member,
  required Map<String, MasterCharacter> characters,
  required ValueChanged<List<TeamTemplateMember>>? onApplyTeam,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder:
        (_) => _ReplacementCandidateSheet(
          template: template,
          member: member,
          characters: characters,
          onApplyTeam: onApplyTeam,
        ),
  );
}

class _ReplacementCandidateSheet extends ConsumerStatefulWidget {
  const _ReplacementCandidateSheet({
    required this.template,
    required this.member,
    required this.characters,
    required this.onApplyTeam,
  });

  final PublishedTeamTemplate template;
  final TeamTemplateMember member;
  final Map<String, MasterCharacter> characters;
  final ValueChanged<List<TeamTemplateMember>>? onApplyTeam;

  @override
  ConsumerState<_ReplacementCandidateSheet> createState() =>
      _ReplacementCandidateSheetState();
}

class _ReplacementCandidateSheetState
    extends ConsumerState<_ReplacementCandidateSheet> {
  bool _ownedOnly = false;
  bool _builtFirst = true;
  bool _optimalOnly = false;
  bool _includeConditional = true;
  String _element = 'all';
  String _role = 'all';

  @override
  Widget build(BuildContext context) {
    final key = TeamReplacementKey(
      widget.template.id,
      widget.member.characterId,
    );
    final state = ref.watch(teamReplacementDisplayProvider(key));
    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        expand: false,
        builder:
            (context, scrollController) => state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (_, __) => _CandidateFailure(
                    onRetry:
                        () =>
                            ref.invalidate(teamReplacementDisplayProvider(key)),
                  ),
              data: (display) => _content(context, scrollController, display),
            ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ScrollController controller,
    TeamReplacementDisplayResult display,
  ) {
    final elements =
        display.candidates
            .map((value) => value.candidate.element)
            .where((value) => value != 'unknown')
            .toSet()
            .toList()
          ..sort();
    final roles =
        display.candidates
            .expand((value) => value.candidate.roles)
            .toSet()
            .toList()
          ..sort();
    final candidates =
        display.candidates.where((displayCandidate) {
          final candidate = displayCandidate.candidate;
          if (_ownedOnly && !displayCandidate.isOwned) return false;
          if (_optimalOnly &&
              candidate.category != ReplacementCategory.optimal) {
            return false;
          }
          if (!_includeConditional &&
              candidate.category == ReplacementCategory.conditional) {
            return false;
          }
          if (candidate.category == ReplacementCategory.notRecommended) {
            return false;
          }
          if (_element != 'all' && candidate.element != _element) return false;
          if (_role != 'all' && !candidate.roles.contains(_role)) return false;
          return true;
        }).toList();
    if (_builtFirst) {
      candidates.sort(
        (a, b) =>
            b.readinessScore.compareTo(a.readinessScore) != 0
                ? b.readinessScore.compareTo(a.readinessScore)
                : b.overallScore.compareTo(a.overallScore),
      );
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${_characterName(widget.characters, widget.member.characterId)}の入れ替え候補',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _filters(elements, roles),
        if (display.readinessLimited)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('HoYoLAB育成情報を取得できないため、ローカル登録分だけで育成準備度を表示しています。'),
          ),
        if (display.result.replacementRisks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(display.result.replacementRisks.join('／')),
          ),
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('条件に合う候補がありません。')),
          ),
        for (final candidate in candidates)
          _CandidateCard(
            display: candidate,
            character: widget.characters[candidate.candidate.characterId],
            generatedAt: display.result.generatedAt,
            source: display.result.source,
            onTap: () => _preview(context, candidate),
          ),
      ],
    );
  }

  Widget _filters(List<String> elements, List<String> roles) {
    return Column(
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('所持キャラのみ'),
          value: _ownedOnly,
          onChanged: (value) => setState(() => _ownedOnly = value),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('育成済みを優先'),
          value: _builtFirst,
          onChanged: (value) => setState(() => _builtFirst = value),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: const Text('最適候補のみ'),
              selected: _optimalOnly,
              onSelected: (value) => setState(() => _optimalOnly = value),
            ),
            FilterChip(
              label: const Text('条件付きを含む'),
              selected: _includeConditional,
              onSelected:
                  (value) => setState(() => _includeConditional = value),
            ),
            DropdownButton<String>(
              value: _element,
              items: [
                const DropdownMenuItem(value: 'all', child: Text('全元素')),
                for (final value in elements)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_elementLabel(value)),
                  ),
              ],
              onChanged: (value) => setState(() => _element = value ?? 'all'),
            ),
            DropdownButton<String>(
              value: _role,
              items: [
                const DropdownMenuItem(value: 'all', child: Text('全役割')),
                for (final value in roles)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_roleLabel(value)),
                  ),
              ],
              onChanged: (value) => setState(() => _role = value ?? 'all'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _preview(
    BuildContext sheetContext,
    ReplacementCandidateDisplay candidate,
  ) async {
    final members = [
      for (final member in widget.template.members)
        TeamTemplateMember(
          characterId:
              member.characterId == widget.member.characterId
                  ? candidate.candidate.characterId
                  : member.characterId,
          role: member.role,
          slotIndex: member.slotIndex,
        ),
    ]..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    final canApply =
        members.length == 4 &&
        members.map((member) => member.characterId).toSet().length == 4 &&
        members.map((member) => member.slotIndex).toSet().length == 4;
    final apply = await showDialog<bool>(
      context: sheetContext,
      builder:
          (context) => AlertDialog(
            title: const Text('置き換え後の編成'),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final member in members)
                  Chip(
                    label: Text(
                      _characterName(widget.characters, member.characterId),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('戻る'),
              ),
              FilledButton(
                onPressed:
                    canApply ? () => Navigator.of(context).pop(true) : null,
                child: Text(widget.onApplyTeam == null ? '閉じる' : '編成に反映'),
              ),
            ],
          ),
    );
    if (apply == true && mounted && sheetContext.mounted) {
      widget.onApplyTeam?.call(members);
      Navigator.of(sheetContext).pop();
    }
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.display,
    required this.character,
    required this.generatedAt,
    required this.source,
    required this.onTap,
  });

  final ReplacementCandidateDisplay display;
  final MasterCharacter? character;
  final DateTime generatedAt;
  final String source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final candidate = display.candidate;
    final theme = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: GameIconImage(
                  iconUrl: character?.iconUrl ?? '',
                  size: 44,
                  borderRadius: 8,
                  fallback: Text((character?.name ?? '?')[0]),
                ),
                title: Text(character?.name ?? candidate.characterId),
                subtitle: Text(
                  '${_categoryLabel(candidate.category)}／'
                  '${display.isOwned ? '所持済み' : '未所持'}'
                  '${display.build == null ? '' : '／Lv.${display.build!.level}'}',
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
              _score('編成適性', candidate.finalScore, theme),
              _score('育成準備度', display.readinessScore, theme),
              _score('総合おすすめ度', display.overallScore, theme),
              for (final reason in candidate.reasons) Text('・$reason'),
              for (final tradeoff in candidate.tradeoffs)
                Text('失う機能: $tradeoff', style: theme.textTheme.bodySmall),
              for (final change in candidate.requiredChanges)
                Text('必要な変更: $change', style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                '評価: ${switch (source) {
                  'deepseek' => '事前AI評価＋ルール検証',
                  'manual' => '管理者確認済み',
                  _ => 'ルール評価',
                }}／'
                '${generatedAt.toLocal().toString().split(' ').first}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _score(String label, double value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label)),
          Expanded(
            child: LinearProgressIndicator(value: value.clamp(0, 100) / 100),
          ),
          const SizedBox(width: 8),
          Text(value.toStringAsFixed(0), style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _CandidateFailure extends StatelessWidget {
  const _CandidateFailure({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('入れ替え候補を取得できませんでした。'),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('再試行'),
          ),
        ],
      ),
    );
  }
}

String _characterName(
  Map<String, MasterCharacter> characters,
  String characterId,
) => characters[characterId]?.name ?? characterId;

String _sourceLabel(String source) => switch (source) {
  'genshinbuilds' => 'GenshinBuilds',
  'manual' => '手動登録',
  _ => '承認済みローカルデータ',
};

String _categoryLabel(ReplacementCategory category) => switch (category) {
  ReplacementCategory.optimal => '最適',
  ReplacementCategory.conditional => '条件付き',
  ReplacementCategory.compromise => '妥協',
  ReplacementCategory.notRecommended => '非推奨',
};

String _elementLabel(String element) => switch (element) {
  'pyro' => '炎',
  'hydro' => '水',
  'electro' => '雷',
  'cryo' => '氷',
  'anemo' => '風',
  'geo' => '岩',
  'dendro' => '草',
  _ => element,
};

String _roleLabel(String role) => switch (role) {
  'main_dps' => 'メインアタッカー',
  'sub_dps' => 'サブアタッカー',
  'support' => 'サポート',
  'healer' => 'ヒーラー',
  'shielder' => 'シールド',
  'flex' => '自由枠',
  _ => role,
};
