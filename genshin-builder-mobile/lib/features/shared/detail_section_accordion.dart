import 'package:flutter/material.dart';

/// キャラ詳細の各セクション用アコーディオン（閉じたとき概要表示）
class DetailSectionAccordion extends StatefulWidget {
  const DetailSectionAccordion({
    super.key,
    required this.title,
    required this.summary,
    required this.child,
    this.defaultOpen = false,
  });

  final String title;
  final Widget summary;
  final Widget child;
  final bool defaultOpen;

  @override
  State<DetailSectionAccordion> createState() => _DetailSectionAccordionState();
}

class _DetailSectionAccordionState extends State<DetailSectionAccordion> {
  late bool _open = widget.defaultOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        DefaultTextStyle(
                          style: (Theme.of(context).textTheme.bodyMedium ??
                                  const TextStyle())
                              .copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                          child: widget.summary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          if (_open)
            Padding(
              padding: const EdgeInsets.all(16),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}
