import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/child_profile.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/async_view.dart';
import '../../shared/theme.dart';
import 'child_board_card.dart';
import 'notifications_screen.dart';
import 'parent_providers.dart';
import 'suggested_quests.dart';

/// The Board tab: the code that pairs a child's phone, each child with what
/// they have earned against their own caps (BD1), and quests to give out
/// (BD2). The shell above it holds the bar, the tabs and the Add child
/// button (PN1).
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

    final feed = ref.watch(reviewFeedProvider);
    final waiting = feed.hasValue ? feed.requireValue.waiting.length : 0;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(childrenProvider);
        await ref.read(reviewFeedProvider.notifier).refresh();
        await ref.read(childrenProvider.future);
      },
      child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Room at the bottom so the button never covers the last child.
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text(
              'Hello, ${parent.name}',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (waiting > 0) ...[
              const SizedBox(height: 16),
              _WaitingCard(count: waiting),
            ],
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
            const SizedBox(height: 24),
            const SuggestedQuests(),
          ],
        ),
    );
  }
}

/// Photos the checker left to a grown-up, and the way to them. The bell
/// carries the same list (NT2); this is here because a photo waiting is the
/// one thing on this screen that cannot wait.
class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tint = QuestColors.of(context).review;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      color: tint.fill,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.flag_rounded, color: tint.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1 ? '1 photo needs your review' : '$count photos need your review',
                  style: text.titleSmall?.copyWith(color: tint.ink, fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.chevron_right, color: tint.ink),
            ],
          ),
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
