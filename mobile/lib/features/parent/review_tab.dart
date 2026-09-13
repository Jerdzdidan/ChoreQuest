import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/submission.dart';
import '../../shared/async_view.dart';
import '../../shared/avatars.dart';
import '../../shared/submission_photo.dart';
import 'parent_providers.dart';
import 'review_labels.dart';
import 'review_watcher.dart';
import 'submission_review_screen.dart';

enum _Show { waiting, recent }

/// Photos waiting for a decision, and a look back over recent ones.
class ReviewTab extends ConsumerStatefulWidget {
  const ReviewTab({super.key});

  @override
  ConsumerState<ReviewTab> createState() => _ReviewTabState();
}

class _ReviewTabState extends ConsumerState<ReviewTab> {
  var _show = _Show.waiting;

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(reviewFeedProvider);
    final children = ref.watch(childrenProvider);
    final avatars = <int, String>{
      if (children.hasValue)
        for (final child in children.requireValue) child.id: child.avatar,
    };
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final loaded = feed.hasValue ? feed.requireValue : null;
    final waitingCount = loaded?.waiting.length ?? 0;
    final list = switch (_show) {
      _Show.waiting => loaded?.waiting,
      _Show.recent => loaded?.recent,
    };

    final header = <Widget>[
      Text(
        switch (_show) {
          _Show.waiting =>
            "Photos the checker wasn't sure about, and chores it can't check.",
          _Show.recent => 'The latest photos, including those the checker '
              'decided. Open one to confirm or change it.',
        },
        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 12),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: Column(
        children: [
          // Stays put while the list scrolls, so switching lists never means
          // scrolling back to the top first.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_Show>(
                segments: [
                  ButtonSegment(
                    value: _Show.waiting,
                    label: Text(
                      waitingCount == 0
                          ? 'Waiting'
                          : 'Waiting ($waitingCount)',
                    ),
                  ),
                  const ButtonSegment(
                    value: _Show.recent,
                    label: Text('All recent'),
                  ),
                ],
                selected: {_show},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _show = selection.first),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(reviewFeedProvider.notifier).refresh(),
              // Built lazily, so only the photos on screen are downloaded.
              child: ListView.builder(
                // Scrollable even when short, so pulling down always refreshes.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: header.length +
                    (list == null || list.isEmpty ? 1 : list.length),
                itemBuilder: (context, index) {
                  if (index < header.length) return header[index];
                  if (list == null) {
                    return AsyncView<ReviewFeed>(
                      value: feed,
                      onRetry: () => ref.invalidate(reviewFeedProvider),
                      builder: (_, _) => const SizedBox.shrink(),
                    );
                  }
                  if (list.isEmpty) return _Empty(show: _show);

                  final submission = list[index - header.length];
                  return _SubmissionTile(
                    submission: submission,
                    avatar: avatars[submission.childId],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({required this.submission, required this.avatar});

  final Submission submission;
  final String? avatar;

  @override
  Widget build(BuildContext context) {
    final s = submission;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SubmissionReviewScreen(submission: s),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 76,
                  child: SubmissionPhoto(url: s.photoUrl, decodeWidth: 228),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AvatarBadge(avatar ?? '', size: 22),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            s.childName ?? 'Child',
                            style: text.labelLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.choreName ?? 'Chore',
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      sentLabel(context, s.submittedAt),
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    DecisionChip(submission: s),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.show});

  final _Show show;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (icon, title, message) = switch (show) {
      _Show.waiting => (
          Icons.task_alt_rounded,
          'Nothing to check',
          'Photos that need you will show up here.',
        ),
      _Show.recent => (
          Icons.photo_library_outlined,
          'No photos yet',
          'Photos your children send will show up here.',
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
