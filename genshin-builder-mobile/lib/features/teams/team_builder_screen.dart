import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../application/element_colors.dart';
import '../../domain/game_display.dart';
import '../../domain/models/master_models.dart';
import '../../domain/team/team_models.dart';
import '../../providers/app_providers.dart';
import '../../providers/growth_providers.dart';
import '../../core/errors/user_facing_error.dart';
import '../shared/game_icon_image.dart';

// ---------------------------------------------------------------------------
// Team role
// ---------------------------------------------------------------------------

enum TeamRole {
  mainDps,
  subDps,
  support,
  healer,
  shielder,
  flex,
}

extension TeamRoleLabel on TeamRole {
  String get label {
    switch (this) {
      case TeamRole.mainDps:
        return '\u30e1\u30a4\u30f3\u30a2\u30bf\u30c3\u30ab\u30fc';
      case TeamRole.subDps:
        return '\u30b5\u30d6\u30a2\u30bf\u30c3\u30ab\u30fc';
      case TeamRole.support:
        return '\u30b5\u30dd\u30fc\u30c8';
      case TeamRole.healer:
        return '\u30d2\u30fc\u30e9\u30fc';
      case TeamRole.shielder:
        return '\u30b7\u30fc\u30eb\u30c9';
      case TeamRole.flex:
        return '\u81ea\u7531\u67a0';
    }
  }
}

/// Default roles for slots 0-3.
const _defaultRoles = [TeamRole.mainDps, TeamRole.subDps, TeamRole.support, TeamRole.healer];

// ---------------------------------------------------------------------------
// TeamBuilderSlot (UI state)
// ---------------------------------------------------------------------------

class TeamBuilderSlot {
  const TeamBuilderSlot({this.characterId, this.role = TeamRole.mainDps});

  final String? characterId;
  final TeamRole role;

  bool get isEmpty => characterId == null;

  TeamBuilderSlot copyWith({String? characterId, TeamRole? role}) =>
      TeamBuilderSlot(characterId: characterId ?? this.characterId, role: role ?? this.role);
}

// ---------------------------------------------------------------------------
// TeamBuilderScreen
// ---------------------------------------------------------------------------

class TeamBuilderScreen extends ConsumerStatefulWidget {
  const TeamBuilderScreen({super.key});

  @override
  ConsumerState<TeamBuilderScreen> createState() => _TeamBuilderScreenState();
}

class _TeamBuilderScreenState extends ConsumerState<TeamBuilderScreen> {
  final String _teamId = const Uuid().v4();
  final List<TeamBuilderSlot> _slots = [
    const TeamBuilderSlot(),
    const TeamBuilderSlot(),
    const TeamBuilderSlot(),
    const TeamBuilderSlot(),
  ];

  late final TextEditingController _teamNameController = TextEditingController();
  bool _isPickerOpen = false;
  bool _isRolePickerOpen = false;

  int get _selectedCount => _slots.where((s) => !s.isEmpty).length;
  bool get _isComplete => _selectedCount == 4;

  Set<String> get _selectedIds {
    return _slots
        .where((s) => !s.isEmpty)
        .map((s) => s.characterId!)
        .map((id) => _isTravelerId(id) ? 'traveler' : id)
        .toSet();
  }

  static bool _isTravelerId(String id) {
    final base = id.split('-').first;
    return base == '10000005' || base == '10000007';
  }

  // ── Character picker ──────────────────────────────────────────────

  Future<void> _openCharacterPicker(int slotIndex) async {
    if (_isPickerOpen || _isRolePickerOpen) return;
    _dismissKeyboard();

    setState(() => _isPickerOpen = true);

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TeamCharacterPicker(
        selectedIds: _selectedIds,
        onSelected: (id) => Navigator.of(context).pop(id),
      ),
    );

    if (!mounted) return;
    if (selectedId == null) {
      setState(() => _isPickerOpen = false);
      return;
    }

    setState(() {
      _slots[slotIndex] = _slots[slotIndex].copyWith(characterId: selectedId);
      _isPickerOpen = false;
    });
  }

  // ── Role picker ───────────────────────────────────────────────────

  Future<void> _openRolePicker(int slotIndex) async {
    if (_isPickerOpen || _isRolePickerOpen) return;
    _dismissKeyboard();

    setState(() => _isRolePickerOpen = true);

    final newRole = await showModalBottomSheet<TeamRole>(
      context: context,
      builder: (_) => _RolePickerSheet(currentRole: _slots[slotIndex].role),
    );

    if (!mounted) return;
    setState(() => _isRolePickerOpen = false);
    if (newRole == null) return;

    setState(() {
      _slots[slotIndex] = _slots[slotIndex].copyWith(role: newRole);
    });
  }

  // ── Reorder ───────────────────────────────────────────────────────

  void _moveSlot(int fromIndex, int toIndex) {
    if (fromIndex == toIndex) return;
    setState(() {
      final fromSlot = _slots[fromIndex];
      final toSlot = _slots[toIndex];
      if (fromSlot.isEmpty && toSlot.isEmpty) return;
      _slots[fromIndex] = toSlot;
      _slots[toIndex] = fromSlot;
    });
  }

  // ── Mutations ─────────────────────────────────────────────────────

  void _removeCharacter(int slotIndex) {
    setState(() => _slots[slotIndex] = TeamBuilderSlot(
          role: _defaultRoles[slotIndex],
        ));
  }

  void _clearAll() {
    setState(() {
      _teamNameController.clear();
      for (var i = 0; i < _slots.length; i++) {
        _slots[i] = TeamBuilderSlot(role: _defaultRoles[i]);
      }
    });
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  // ── Future hint ────────────────────────────────────────────────────────

  Future<void> _openTeamPriority(BuildContext context) async {
    if (_selectedCount == 0) return;
    final team = Team(
      id: _teamId,
      name: _teamNameController.text.trim().isEmpty
          ? '\u7121\u984c\u306e\u7de8\u6210'
          : _teamNameController.text.trim(),
      members: [
        for (var i = 0; i < _slots.length; i++)
          if (!_slots[i].isEmpty)
            TeamMemberSlot(characterId: _slots[i].characterId!, position: i),
      ],
    );
    final userId = await ref.read(localUserIdProvider.future);
    final repository = await ref.read(teamRepoProvider.future);
    await repository.save(userId, team);
    ref.invalidate(accountSnapshotProvider);
    ref.invalidate(accountHealthReportProvider);
    if (!context.mounted) return;
    await context.push('/team-priority', extra: team.id);
  }

  Widget _buildTeamPriorityButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _selectedCount == 0
          ? null
          : () => _openTeamPriority(context),
      icon: const Icon(Icons.sort),
      label: const Text('\u3053\u306e\u7de8\u6210\u306e\u80b2\u6210\u512a\u5148\u5ea6\u3092\u898b\u308b'),
    );
  }

  Widget _buildFutureHint(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('\u304a\u3059\u3059\u3081\u7de8\u6210', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '\u304a\u3059\u3059\u3081\u7de8\u6210\u6a5f\u80fd\u306f\u4eca\u5f8c\u8ffd\u52a0\u4e88\u5b9a\u3067\u3059',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  void dispose() {
    _teamNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: _dismissKeyboard,
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('\u7de8\u6210'),
          actions: [
            if (_slots.any((s) => !s.isEmpty))
              IconButton(
                icon: const Icon(Icons.clear_all),
                tooltip: '\u7de8\u6210\u3092\u30af\u30ea\u30a2',
                onPressed: () => _confirmClear(context),
              ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTeamName(theme),
                const SizedBox(height: 12),
                _buildCompletionStatus(theme),
                const SizedBox(height: 8),
                _buildHintText(theme),
                const SizedBox(height: 12),
                _buildSlots(),
                const SizedBox(height: 16),
                if (_selectedCount > 0)
                  _buildTeamPriorityButton(context),
                const SizedBox(height: 24),
                _buildFutureHint(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamName(ThemeData theme) {
    return Semantics(
      label: '\u7de8\u6210\u540d\u5165\u529b',
      child: TextField(
        controller: _teamNameController,
        maxLength: 24,
        decoration: InputDecoration(
          labelText: '\u7de8\u6210\u540d',
          hintText: '\u7121\u984c\u306e\u7de8\u6210',
          isDense: true,
          border: const OutlineInputBorder(),
          counterStyle: theme.textTheme.labelSmall,
        ),
      ),
    );
  }

  Widget _buildCompletionStatus(ThemeData theme) {
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: _isComplete
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurfaceVariant,
    );
    final text = _isComplete
        ? '$_selectedCount / 4 \u3000\u7de8\u6210\u304c\u5b8c\u6210\u3057\u307e\u3057\u305f'
        : '$_selectedCount / 4 \u3000\u3042\u3068${4 - _selectedCount}\u4eba\u9078\u629e\u3057\u3066\u304f\u3060\u3055\u3044';
    return Semantics(
      label: text,
      child: Text(text, style: style),
    );
  }

  Widget _buildHintText(ThemeData theme) {
    return Text(
      '\u30bf\u30c3\u30d7\u3067\u5909\u66f4\u30fb\u9577\u62bc\u3057\u3067\u4e26\u3073\u66ff\u3048',
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildSlots() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 480 ? 4 : 2;
        const spacing = 8.0;
        final totalSpacing = spacing * (columns - 1);
        final slotWidth = (constraints.maxWidth - totalSpacing) / columns;
        final slotHeight = slotWidth * 1.35;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < 4; i++)
              SizedBox(
                width: slotWidth,
                height: slotHeight,
                child: _DraggableSlot(
                  slotIndex: i,
                  slot: _slots[i],
                  columns: columns,
                  slotHeight: slotHeight,
                  onTap: () => _openCharacterPicker(i),
                  onRoleTap: () => _openRolePicker(i),
                  onRemove: !_slots[i].isEmpty
                      ? () => _removeCharacter(i)
                      : null,
                  onMove: _moveSlot,
                ),
              ),
          ],
        );
      },
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('\u7de8\u6210\u3092\u30af\u30ea\u30a2'),
        content: const Text(
          '\u9078\u629e\u3057\u305f\u30ad\u30e3\u30e9\u30af\u30bf\u30fc\u3001\u5f79\u5272\u3001\u7de8\u6210\u540d\u304c\u3059\u3079\u3066\u521d\u671f\u72b6\u614b\u306b\u623b\u308a\u307e\u3059\u3002',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('\u30ad\u30e3\u30f3\u30bb\u30eb'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _clearAll();
            },
            child: const Text('\u30af\u30ea\u30a2'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Draggable slot wrapper — wraps each slot in LongPressDraggable / DragTarget
// ---------------------------------------------------------------------------

class _DraggableSlot extends StatelessWidget {
  const _DraggableSlot({
    required this.slotIndex,
    required this.slot,
    required this.columns,
    required this.slotHeight,
    required this.onTap,
    required this.onRoleTap,
    required this.onRemove,
    required this.onMove,
  });

  final int slotIndex;
  final TeamBuilderSlot slot;
  final int columns;
  final double slotHeight;
  final VoidCallback onTap;
  final VoidCallback onRoleTap;
  final VoidCallback? onRemove;
  final void Function(int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    final child = _TeamSlot(
      slotIndex: slotIndex,
      slot: slot,
      onTap: onTap,
      onRoleTap: onRoleTap,
      onRemove: onRemove,
      showDragHandle: !slot.isEmpty,
      isDragOver: false,
    );

    if (slot.isEmpty) {
      return DragTarget<int>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (d) => onMove(d.data, slotIndex),
        builder: (_, __, ___) => child,
      );
    }

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != slotIndex,
      onAcceptWithDetails: (d) => onMove(d.data, slotIndex),
      builder: (_, candidateData, rejectedData) {
        final isDragOver = candidateData.isNotEmpty;
        return LongPressDraggable<int>(
          data: slotIndex,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: SizedBox(
            width: 120,
            height: 120,
            child: _TeamSlot(
              slotIndex: slotIndex,
              slot: slot,
              onTap: () {},
              onRoleTap: () {},
              onRemove: null,
              showDragHandle: false,
              isDragOver: false,
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: child,
          ),
          child: isDragOver
              ? _TeamSlot(
                  slotIndex: slotIndex,
                  slot: slot,
                  onTap: onTap,
                  onRoleTap: onRoleTap,
                  onRemove: onRemove,
                  showDragHandle: true,
                  isDragOver: true,
                )
              : child,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Team slot widget
// ---------------------------------------------------------------------------

class _TeamSlot extends ConsumerWidget {
  const _TeamSlot({
    required this.slotIndex,
    required this.slot,
    required this.onTap,
    required this.onRoleTap,
    this.onRemove,
    this.showDragHandle = false,
    this.isDragOver = false,
  });

  final int slotIndex;
  final TeamBuilderSlot slot;
  final VoidCallback onTap;
  final VoidCallback onRoleTap;
  final VoidCallback? onRemove;
  final bool showDragHandle;
  final bool isDragOver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (slot.isEmpty) {
      return _EmptySlot(
        slotNumber: slotIndex + 1,
        defaultRole: _defaultRoles[slotIndex],
        onTap: onTap,
      );
    }

    final charsAsync = ref.watch(charactersProvider);
    return charsAsync.when(
      data: (characters) {
        final character = characters.cast<MasterCharacter?>().firstWhere(
              (c) => c?.id == slot.characterId,
              orElse: () => null,
            );
        if (character == null) {
          return _EmptySlot(
            slotNumber: slotIndex + 1,
            defaultRole: slot.role,
            onTap: onTap,
          );
        }
        return _FilledSlot(
          slotNumber: slotIndex + 1,
          character: character,
          role: slot.role,
          onTap: onTap,
          onRoleTap: onRoleTap,
          onRemove: onRemove,
          showDragHandle: showDragHandle,
          isDragOver: isDragOver,
        );
      },
      loading: () => _EmptySlot(
        slotNumber: slotIndex + 1,
        defaultRole: slot.role,
        onTap: onTap,
      ),
      error: (_, __) => _EmptySlot(
        slotNumber: slotIndex + 1,
        defaultRole: slot.role,
        onTap: onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty slot
// ---------------------------------------------------------------------------

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({
    required this.slotNumber,
    required this.defaultRole,
    required this.onTap,
  });

  final int slotNumber;
  final TeamRole defaultRole;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$slotNumber\u4eba\u76ee\u306e\u30ad\u30e3\u30e9\u30af\u30bf\u30fc\u3092\u9078\u629e',
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  label: Text('$slotNumber'),
                  child: Icon(
                    Icons.person_add_alt_1_outlined,
                    size: 28,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '\u30ad\u30e3\u30e9\u3092\u9078\u629e',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  defaultRole.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filled slot
// ---------------------------------------------------------------------------

class _FilledSlot extends StatelessWidget {
  const _FilledSlot({
    required this.slotNumber,
    required this.character,
    required this.role,
    required this.onTap,
    required this.onRoleTap,
    this.onRemove,
    this.showDragHandle = false,
    this.isDragOver = false,
  });

  final int slotNumber;
  final MasterCharacter character;
  final TeamRole role;
  final VoidCallback onTap;
  final VoidCallback onRoleTap;
  final VoidCallback? onRemove;
  final bool showDragHandle;
  final bool isDragOver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = isDragOver
        ? theme.colorScheme.primary
        : character.element.elementColor;
    final borderWidth = isDragOver ? 3.0 : 2.0;
    final label =
        '$slotNumber\u4eba\u76ee ${character.name}\u3000${role.label}\u3000\u4e26\u3073\u66ff\u3048\u53ef\u80fd';

    return Semantics(
      label: label,
      child: Material(
        color: isDragOver
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 2),
          child: Stack(
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Center(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: onTap,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final size =
                                  constraints.biggest.shortestSide.clamp(36.0, 64.0);
                              return GameIconImage(
                                iconUrl: character.iconUrl,
                                size: size,
                                borderRadius: 8,
                                borderColor: character.element.elementColor,
                                fallback: Text(
                                  character.name.isNotEmpty ? character.name[0] : '?',
                                  style: theme.textTheme.titleMedium,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    character.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 2),
                  _RoleChip(role: role, onTap: onRoleTap),
                ],
              ),
              // Top-left: slot number
              Positioned(
                left: 0,
                top: 0,
                child: Badge(label: Text('$slotNumber')),
              ),
              // Top-right: remove button
              if (onRemove != null)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Semantics(
                    label: '\u524a\u9664',
                    child: InkResponse(
                      radius: 15,
                      onTap: onRemove,
                      child: Icon(Icons.cancel, size: 20, color: theme.colorScheme.error),
                    ),
                  ),
                ),
              // Drag handle
              if (showDragHandle)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Semantics(
                    label: '\u4e26\u3073\u66ff\u3048',
                    child: Icon(Icons.drag_indicator,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Role chip
// ---------------------------------------------------------------------------

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role, required this.onTap});

  final TeamRole role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '\u5f79\u5272: ${role.label}\u3000\u30bf\u30c3\u30d7\u3067\u5909\u66f4',
      child: ActionChip(
        label: Text(role.label, style: theme.textTheme.labelSmall),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Role picker (BottomSheet)
// ---------------------------------------------------------------------------

class _RolePickerSheet extends StatelessWidget {
  const _RolePickerSheet({required this.currentRole});

  final TeamRole currentRole;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Text('\u5f79\u5272\u3092\u9078\u629e', style: theme.textTheme.titleSmall),
            ),
            RadioGroup<TeamRole>(
              groupValue: currentRole,
              onChanged: (v) => Navigator.of(context).pop(v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final r in TeamRole.values)
                    RadioListTile<TeamRole>(
                      title: Text(r.label),
                      value: r,
                      dense: true,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Character picker (BottomSheet) — unchanged from Phase 1 audit
// ---------------------------------------------------------------------------

class _TeamCharacterPicker extends ConsumerWidget {
  const _TeamCharacterPicker({
    required this.selectedIds,
    required this.onSelected,
  });

  final Set<String> selectedIds;
  final ValueChanged<String> onSelected;

  static bool _isTravelerId(String id) {
    final base = id.split('-').first;
    return base == '10000005' || base == '10000007';
  }

  bool _isExcluded(String characterId) {
    if (_isTravelerId(characterId)) {
      return selectedIds.contains('traveler');
    }
    return selectedIds.contains(characterId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charsAsync = ref.watch(charactersProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => charsAsync.when(
        data: (characters) => _CharacterPickerContent(
          characters: characters,
          isExcluded: _isExcluded,
          onSelected: onSelected,
          scrollController: scrollController,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(userFacingError(e))),
      ),
    );
  }
}

class _CharacterPickerContent extends StatefulWidget {
  const _CharacterPickerContent({
    required this.characters,
    required this.isExcluded,
    required this.onSelected,
    required this.scrollController,
  });

  final List<MasterCharacter> characters;
  final bool Function(String characterId) isExcluded;
  final ValueChanged<String> onSelected;
  final ScrollController scrollController;

  @override
  State<_CharacterPickerContent> createState() => _CharacterPickerContentState();
}

class _CharacterPickerContentState extends State<_CharacterPickerContent> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = widget.characters
        .where((c) => !widget.isExcluded(c.id))
        .toList();

    final filtered = _query.isEmpty
        ? available
        : available
            .where((c) =>
                c.name.contains(_query) ||
                c.element.contains(_query.toLowerCase()))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '\u30ad\u30e3\u30e9\u691c\u7d22',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    '\u30ad\u30e3\u30e9\u30af\u30bf\u30fc\u304c\u898b\u3064\u304b\u308a\u307e\u305b\u3093',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : GridView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final c = filtered[index];
                    final elementLabel = elementLabelMap[c.element] ?? c.element;
                    return Material(
                      color: theme.colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => widget.onSelected(c.id),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Center(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final size = constraints.biggest.shortestSide
                                          .clamp(32.0, 56.0);
                                      return GameIconImage(
                                        iconUrl: c.iconUrl,
                                        size: size,
                                        borderRadius: 8,
                                        borderColor: c.element.elementColor,
                                        fallback: Text(
                                          c.name.isNotEmpty ? c.name[0] : '?',
                                          style: theme.textTheme.titleMedium,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelSmall,
                              ),
                              Text(
                                '$elementLabel \u00b7 ${c.rarity}\u2605',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
