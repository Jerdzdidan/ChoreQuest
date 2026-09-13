import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/submission.dart';
import '../../shared/avatars.dart';
import '../../shared/inline_error.dart';
import '../../shared/submission_photo.dart';
import 'parent_providers.dart';
import 'review_labels.dart';

/// One answer a parent can give.
class _Answer {
  const _Answer(this.label, {this.confirm});

  final String label;

  /// The title and message to confirm with first, for an answer that moves
  /// screen time against what the checker decided.
  final (String, String)? confirm;
}

/// One photo, large, with what the checker made of it and the parent's answer.
///
/// The parent may confirm or overturn any decision, the checker's included.
/// Confirming an automatic one is worth a tap: it is the only way that
/// decision gains a ground truth for the study's error rates.
class SubmissionReviewScreen extends ConsumerStatefulWidget {
  const SubmissionReviewScreen({super.key, required this.submission});

  final Submission submission;

  @override
  ConsumerState<SubmissionReviewScreen> createState() =>
      _SubmissionReviewScreenState();
}

class _SubmissionReviewScreenState
    extends ConsumerState<SubmissionReviewScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _answer({
    required bool approve,
    (String, String)? confirm,
  }) async {
    if (confirm != null) {
      final (title, message) = confirm;
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(approve ? 'Approve' : 'Send back'),
            ),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final chore = widget.submission.choreName ?? 'the chore';
    try {
      await ref
          .read(parentApiProvider)
          .decide(widget.submission.id, approved: approve);
      if (mounted) _close(approve ? 'Approved: $chore.' : 'Sent back: $chore.');
    } on ApiRejected catch (e) {
      if (!mounted) return;
      // 409: decided differently on another phone first, or a photo whose
      // screen time was already taken back once. Either way this screen is out
      // of date, so go back to a fresh list with the server's explanation.
      if (e.statusCode == 409) {
        _close(e.message);
      } else {
        setState(() => _error = e.message);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _close(String message) {
    ref.read(reviewFeedProvider.notifier).refresh();
    // A decision can move screen time, so an open report is out of date.
    ref.invalidate(reportProvider);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.submission;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final children = ref.watch(childrenProvider);
    final avatar = children.hasValue
        ? children.requireValue
            .where((c) => c.id == s.childId)
            .firstOrNull
            ?.avatar
        : null;
    final name = s.childName ?? 'Your child';
    final chore = s.choreName ?? 'Chore';
    final error = _error;

    const takeBack = (
      'Send it back?',
      'The screen time this chore earned will be taken away, and this photo '
          "can't be approved again.",
    );
    final give = ('Approve it?', '$name gets the screen time for this chore.');

    final (String question, _Answer? approve, _Answer? reject) =
        switch ((s.parentDecision, s.routing)) {
      (SubmissionStatus.approved, _) => (
          'You approved this photo.',
          null,
          const _Answer('Change to not done', confirm: takeBack),
        ),
      (SubmissionStatus.rejected, _) => (
          'You sent this photo back.',
          _Answer('Change to approved', confirm: give),
          null,
        ),
      (_, Routing.pendingReview) => (
          'Is the chore done?',
          const _Answer('Yes, approve'),
          const _Answer('No, send it back'),
        ),
      (_, Routing.autoApproved) => (
          'The checker approved this and added the screen time. Is it right?',
          const _Answer("Yes, it's done"),
          const _Answer('No, send it back', confirm: takeBack),
        ),
      (_, Routing.autoRejected) => (
          "The checker couldn't see this finished and sent it back. "
              'Is it right?',
          _Answer("It's done, approve it", confirm: give),
          const _Answer("Right, it's not done"),
        ),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Check a photo')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                AvatarBadge(avatar ?? '', size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chore,
                        style: text.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '$name · ${sentLabel(context, s.submittedAt)}',
                        style: text.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                // Big enough to judge the chore, short enough to leave the
                // answer in reach without scrolling on most phones.
                final height = math.min(
                  constraints.maxWidth * 4 / 3,
                  MediaQuery.sizeOf(context).height * 0.55,
                );
                final label = 'Photo of $chore from $name';
                // Zooming happens on a screen of its own: a pinch inside this
                // scrolling list would fight the list for the same gesture.
                return Semantics(
                  button: true,
                  hint: 'Opens the photo full screen',
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) =>
                            _FullPhoto(url: s.photoUrl, label: label),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: ColoredBox(
                        color: Colors.black,
                        child: SizedBox(
                          height: height,
                          width: double.infinity,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              SubmissionPhoto(
                                url: s.photoUrl,
                                fit: BoxFit.contain,
                                semanticLabel: label,
                              ),
                              const Positioned(
                                right: 10,
                                bottom: 10,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.zoom_in_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              color: scheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('What the checker thought', style: text.labelLarge),
                    const SizedBox(height: 4),
                    Text(checkerLabel(s), style: text.bodyLarge),
                    if (isStandIn(s))
                      Text(
                        'From the test stand-in, not the trained model.',
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: 10),
                    DecisionChip(submission: s),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(question, style: text.titleMedium),
            if (error != null) ...[
              const SizedBox(height: 12),
              InlineError(error),
            ],
            const SizedBox(height: 12),
            if (approve != null)
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _answer(approve: true, confirm: approve.confirm),
                icon: const Icon(Icons.check_rounded),
                label: Text(approve.label),
              ),
            if (approve != null && reject != null) const SizedBox(height: 10),
            if (reject != null)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _answer(approve: false, confirm: reject.confirm),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(64, 52),
                ),
                icon: const Icon(Icons.undo_rounded),
                label: Text(reject.label),
              ),
          ],
        ),
      ),
    );
  }
}

/// The photo alone, for a closer look. Pinch to zoom, drag to move around.
class _FullPhoto extends StatelessWidget {
  const _FullPhoto({required this.url, required this.label});

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Photo'),
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: SubmissionPhoto(
            url: url,
            fit: BoxFit.contain,
            semanticLabel: label,
          ),
        ),
      ),
    );
  }
}
