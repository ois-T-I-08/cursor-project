import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// ゲーム内アイコン（素材・武器・聖遺物など）の共通表示
class GameIconImage extends StatelessWidget {
  const GameIconImage({
    super.key,
    this.iconUrl,
    this.size = 40,
    this.fallback,
    this.borderRadius = 6,
  });

  final String? iconUrl;
  final double size;
  final Widget? fallback;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final placeholder = fallback ??
        Icon(Icons.image_not_supported_outlined, size: size * 0.55);

    if (iconUrl == null || iconUrl!.isEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Center(child: placeholder),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: iconUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => SizedBox(
          width: size,
          height: size,
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Center(child: placeholder),
          ),
        ),
      ),
    );
  }
}
