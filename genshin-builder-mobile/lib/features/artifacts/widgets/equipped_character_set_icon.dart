import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/artifacts/artifact_set_overview.dart';
import '../../shared/game_icon_image.dart';

/// 装備キャラアイコン。
/// 中央にキャラ、右上に育成完了✓、2セット時は周囲にセットアイコン（右上以外）。
class EquippedCharacterSetIcon extends StatelessWidget {
  const EquippedCharacterSetIcon({
    super.key,
    required this.entry,
    this.size = 52,
  });

  final ArtifactEquippedCharacter entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final setIconSize = (size * 0.42).clamp(18.0, 28.0);
    final pad = setIconSize * 0.55;
    final total = size + pad * 2;

    final companions =
        entry.isTwoSet ? entry.companionSets : const <ArtifactSetPieceCount>[];
    // 右上は✓用に空け、上・左・下・右下へ配置
    final slots = <Alignment>[
      Alignment.topCenter,
      Alignment.centerLeft,
      Alignment.bottomCenter,
      Alignment.bottomRight,
    ];

    return Tooltip(
      message: _tooltip(entry),
      child: InkWell(
        onTap: () => context.push('/characters/${entry.character.id}'),
        borderRadius: BorderRadius.circular(total / 4),
        child: SizedBox(
          width: total,
          height: total,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              GameIconImage(
                iconUrl: entry.character.iconUrl,
                size: size,
                borderRadius: size / 5,
                fallback: Text(
                  entry.character.name.isNotEmpty
                      ? entry.character.name[0]
                      : '?',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              if (entry.artifactCompleted)
                Positioned(
                  right: pad - 2,
                  top: pad - 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.check,
                      size: size * 0.28,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              for (var i = 0; i < companions.length && i < slots.length; i++)
                Align(
                  alignment: slots[i],
                  child: _SetBadge(set: companions[i], size: setIconSize),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _tooltip(ArtifactEquippedCharacter e) {
    final buf = StringBuffer(e.character.name);
    if (e.isFourSet) {
      buf.write('（4セット）');
    } else if (e.isTwoSet) {
      buf.write('（2セット）');
      for (final s in e.companionSets) {
        buf.write('\n${s.setName} ×${s.count}');
      }
    }
    return buf.toString();
  }
}

class _SetBadge extends StatelessWidget {
  const _SetBadge({required this.set, required this.size});

  final ArtifactSetPieceCount set;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: theme.colorScheme.surface, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.2),
            blurRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: GameIconImage(
          iconUrl: set.iconUrl,
          size: size,
          borderRadius: size / 2,
          fallback: Text(
            set.setName.isNotEmpty ? set.setName[0] : '?',
            style: theme.textTheme.labelSmall?.copyWith(fontSize: size * 0.4),
          ),
        ),
      ),
    );
  }
}
