import 'package:flutter/material.dart';

import '../../domain/team/main_tab.dart';
import '../../router.dart';

/// Moves to the visible secondary-tools tab without duplicating navigation.
class ShellMenuButton extends StatelessWidget {
  const ShellMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.apps_outlined),
      tooltip: 'その他',
      onPressed:
          () => AppShellScope.of(context).switchMainTab(MainTab.more.index),
    );
  }
}
