import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/child_progress.dart';
import '../../shared/async_view.dart';
import 'badge_list.dart';
import 'child_providers.dart';

/// Every badge, earned and still to earn, reached from My Avatar.
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My badges')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AsyncView<ChildProgress>(
            value: progress,
            onRetry: () => ref.invalidate(progressProvider),
            builder: (context, p) {
              final earned = p.badges.where((b) => b.earned).length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$earned of ${p.badges.length} earned',
                    style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  BadgeList(badges: p.badges),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
