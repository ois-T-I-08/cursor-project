import 'package:flutter/material.dart';

import '../../../domain/models/amber_detail_models.dart';
import '../../shared/game_icon_image.dart';

/// 命ノ星座アイコン行（1–6）。タップで凸数を設定、長押しで効果詳細。
class ConstellationIconsRow extends StatelessWidget {
  const ConstellationIconsRow({
    super.key,
    required this.unlockedCount,
    required this.elementColor,
    this.constellations = const [],
    this.onConstellationSelected,
    this.iconSize = 22,
    this.spacing = 4,
  });

  /// 表示用凸数（0〜6）
  final int unlockedCount;

  final Color elementColor;
  final List<ConstellationDetailData> constellations;

  /// 指定時: タップで凸数を変更（1〜6）。0 に戻すには同じ凸を再タップ。
  final ValueChanged<int>? onConstellationSelected;

  final double iconSize;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final count = unlockedCount.clamp(0, 6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 6; i++) ...[
          if (i > 1) SizedBox(width: spacing),
          _ConstellationIconButton(
            position: i,
            unlocked: i <= count,
            elementColor: elementColor,
            size: iconSize,
            detail: i <= constellations.length ? constellations[i - 1] : null,
            onSelect:
                onConstellationSelected == null
                    ? null
                    : () {
                      final next = count == i ? i - 1 : i;
                      onConstellationSelected!(next.clamp(0, 6));
                    },
          ),
        ],
      ],
    );
  }
}

class _ConstellationIconButton extends StatelessWidget {
  const _ConstellationIconButton({
    required this.position,
    required this.unlocked,
    required this.elementColor,
    required this.size,
    this.detail,
    this.onSelect,
  });

  final int position;
  final bool unlocked;
  final Color elementColor;
  final double size;
  final ConstellationDetailData? detail;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimColor = theme.colorScheme.onSurface.withValues(alpha: 0.28);

    return Tooltip(
      message:
          onSelect == null
              ? '命ノ星座 第$position重'
              : 'タップで凸$position（再タップで戻す）· 長押しで効果',
      child: InkWell(
        onTap: onSelect ?? () => _showDetail(context),
        onLongPress: onSelect == null ? null : () => _showDetail(context),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size + 4,
          height: size + 4,
          child: Center(
            child:
                detail?.iconUrl != null
                    ? ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        unlocked ? elementColor : dimColor,
                        BlendMode.srcATop,
                      ),
                      child: GameIconImage(
                        iconUrl: detail!.iconUrl,
                        size: size,
                      ),
                    )
                    : Icon(
                      unlocked ? Icons.circle : Icons.circle_outlined,
                      size: size * 0.85,
                      color: unlocked ? elementColor : dimColor,
                    ),
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final theme = Theme.of(context);
    final name = detail?.name;
    final description = detail?.description;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name?.isNotEmpty == true ? name! : '命ノ星座 第$position重',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  description?.isNotEmpty == true
                      ? description!
                      : '効果テキストを取得できませんでした。',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
