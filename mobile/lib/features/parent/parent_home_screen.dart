import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/child_profile.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/async_view.dart';
import '../../shared/avatars.dart';
import 'child_board_card.dart';
import 'child_form_screen.dart';
import 'notifications_screen.dart';
import 'parent_profile_screen.dart';
import 'parent_providers.dart';

/// The parent's home: their children, and the code that pairs a child's phone.
class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parent = switch (ref.watch(sessionProvider)) {
      AsyncData(value: final ParentSession s) => s,
      _ => null,
    };
    if (parent == null) return const SizedBox.shrink();

    final children = ref.watch(childrenProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Your profile',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Profile')),
                body: const ParentProfileScreen(),
              ),
            ),
          ),
          icon: AvatarBadge(parent.avatar, size: 32),
        ),
        title: const Text('ChoreQuest'),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-child',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ChildFormScreen()),
        ),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add child'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(childrenProvider.future),
        child: ListView(
          // Room at the bottom so the button never covers the last child.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(
              'Hello, ${parent.name}',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            _HouseholdCodeCard(code: parent.householdCode),
            const SizedBox(height: 24),
            Text('Children', style: text.titleMedium),
            const SizedBox(height: 8),
            AsyncView<List<ChildProfile>>(
              value: children,
              onRetry: () => ref.invalidate(childrenProvider),
              builder: (context, list) => list.isEmpty
                  ? const _NoChildrenYet()
                  : Column(
                      children: [
                        for (final child in list) ChildBoardCard(child: child),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HouseholdCodeCard extends StatelessWidget {
  const _HouseholdCodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Household code',
                    style: text.labelLarge
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Type this on your child's phone to set it up. Each phone "
                    'only needs it once.',
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SelectableText(
              code,
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoChildrenYet extends StatelessWidget {
  const _NoChildrenYet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'Add your first child to start giving out chores.',
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
