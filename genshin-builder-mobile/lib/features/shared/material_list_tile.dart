import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models/bookmark.dart';
import 'game_icon_image.dart';

class MaterialListTile extends StatelessWidget {
  const MaterialListTile({
    super.key,
    required this.line,
    required this.isBookmarked,
    required this.onToggleBookmark,
  });

  final RequirementLine line;
  final bool isBookmarked;
  final VoidCallback onToggleBookmark;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###');

    return ListTile(
      leading: line.isMora
          ? const CircleAvatar(child: Text('M'))
          : GameIconImage(
              iconUrl: line.iconUrl,
              size: 40,
              fallback: const Icon(Icons.inventory_2),
            ),
      title: Text(line.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(fmt.format(line.count)),
          IconButton(
            icon: Icon(
              isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: isBookmarked ? Colors.amber : null,
            ),
            onPressed: onToggleBookmark,
          ),
        ],
      ),
    );
  }
}
