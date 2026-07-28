import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/amber_detail_models.dart';
import '../../../providers/character_detail_providers.dart';
import '../../shared/game_icon_image.dart';

/// Skill details (description, multipliers, CT by level)
class SkillDetailsSection extends ConsumerWidget {
  const SkillDetailsSection({
    super.key,
    required this.characterId,
    required this.talentNormal,
    required this.talentSkill,
    required this.talentBurst,
  });

  final String characterId;
  final int talentNormal;
  final int talentSkill;
  final int talentBurst;

  int _currentLevelFor(TalentDetailKind kind) => switch (kind) {
    TalentDetailKind.normal => talentNormal,
    TalentDetailKind.skill => talentSkill,
    TalentDetailKind.burst => talentBurst,
    TalentDetailKind.passive => 1,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(avatarDetailProvider(characterId));

    return detailAsync.when(
      loading:
          () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
      error: (_, __) => const _SkillDetailsUnavailable(),
      data: (detail) {
        if (detail == null || detail.talents.isEmpty) {
          return const _SkillDetailsUnavailable();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('スキル詳細', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...detail.activeTalents.map(
              (talent) => _TalentDetailTile(
                talent: talent,
                initialLevel: _currentLevelFor(talent.kind),
              ),
            ),
            ...detail.passiveTalents.map(
              (talent) => _TalentDetailTile(talent: talent, initialLevel: 1),
            ),
          ],
        );
      },
    );
  }
}

class _SkillDetailsUnavailable extends StatelessWidget {
  const _SkillDetailsUnavailable();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'スキル詳細を取得できませんでした（ネットワーク接続を確認してください）',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TalentDetailTile extends StatefulWidget {
  const _TalentDetailTile({required this.talent, required this.initialLevel});

  final TalentDetailData talent;
  final int initialLevel;

  @override
  State<_TalentDetailTile> createState() => _TalentDetailTileState();
}

class _TalentDetailTileState extends State<_TalentDetailTile> {
  late int _selectedLevel;

  @override
  void initState() {
    super.initState();
    _selectedLevel = _clampLevel(widget.initialLevel);
  }

  @override
  void didUpdateWidget(covariant _TalentDetailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLevel != widget.initialLevel) {
      _selectedLevel = _clampLevel(widget.initialLevel);
    }
  }

  int _clampLevel(int level) {
    final levels = widget.talent.levelStats.keys.toList()..sort();
    if (levels.isEmpty) return level;
    if (levels.contains(level)) return level;
    if (level < levels.first) return levels.first;
    if (level > levels.last) return levels.last;
    return levels.first;
  }

  @override
  Widget build(BuildContext context) {
    final talent = widget.talent;
    final theme = Theme.of(context);
    final kindLabel = talentDetailKindLabels[talent.kind]!;
    final levels = talent.levelStats.keys.toList()..sort();
    final rows = talent.levelStats[_selectedLevel] ?? const [];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: GameIconImage(
          iconUrl: talent.iconUrl,
          size: 36,
          fallback: Text(kindLabel, style: theme.textTheme.labelSmall),
        ),
        title: Text(talent.name, style: theme.textTheme.titleSmall),
        subtitle: Text(
          kindLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(talent.description, style: theme.textTheme.bodySmall),
          if (levels.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text('レベル別数値', style: theme.textTheme.labelLarge),
                const Spacer(),
                DropdownButton<int>(
                  value: _selectedLevel,
                  isDense: true,
                  items:
                      levels
                          .map(
                            (lv) => DropdownMenuItem(
                              value: lv,
                              child: Text('Lv.$lv'),
                            ),
                          )
                          .toList(),
                  onChanged: (lv) {
                    if (lv != null) setState(() => _selectedLevel = lv);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(row.label, style: theme.textTheme.bodySmall),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      row.value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
