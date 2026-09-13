import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/child_profile.dart';
import '../../shared/avatars.dart';
import 'child_chores_tab.dart';
import 'child_form_screen.dart';
import 'child_report_tab.dart';
import 'child_rules_tab.dart';
import 'parent_providers.dart';

enum _MenuAction { edit, remove }

/// One child: their chores, their screen-time rules, and how their screen time
/// has been earned and spent.
class ChildDetailScreen extends ConsumerWidget {
  const ChildDetailScreen({super.key, required this.childId});

  final int childId;

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ChildProfile child,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${child.name}?'),
        content: Text(
          "${child.name}'s chores, photos and screen-time history will be "
          "deleted. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(parentApiProvider).removeChild(child.id);
      ref.invalidate(childrenProvider);
      if (context.mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _onMenu(
    BuildContext context,
    WidgetRef ref,
    ChildProfile child,
    _MenuAction action,
  ) {
    switch (action) {
      case _MenuAction.edit:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChildFormScreen(existing: child)),
        );
      case _MenuAction.remove:
        _remove(context, ref, child);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childrenProvider);
    final child = children.hasValue
        ? children.requireValue.where((c) => c.id == childId).firstOrNull
        : null;

    if (child == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: children.isLoading
              ? const CircularProgressIndicator()
              : const Text('This child is no longer in your household.'),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              AvatarBadge(child.avatar, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(child.name, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<_MenuAction>(
              onSelected: (action) => _onMenu(context, ref, child, action),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _MenuAction.edit,
                  child: Text('Edit profile or PIN'),
                ),
                PopupMenuItem(
                  value: _MenuAction.remove,
                  child: Text('Remove child'),
                ),
              ],
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.checklist), text: 'Chores'),
              Tab(icon: Icon(Icons.tune), text: 'Rules'),
              Tab(icon: Icon(Icons.insights), text: 'Report'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ChildChoresTab(child: child),
            ChildRulesTab(child: child),
            ChildReportTab(child: child),
          ],
        ),
      ),
    );
  }
}
