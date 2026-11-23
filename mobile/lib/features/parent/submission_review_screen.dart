import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/submission.dart';
import '../../shared/avatars.dart';
import '../../shared/format.dart';
import '../../shared/inline_error.dart';
import '../../shared/submission_photo.dart';
import '../../shared/theme.dart';
import 'parent_providers.dart';
import 'review_labels.dart';

/// One answer a parent can give.
class _Answer {
  const _Answer(this.label, {this.confirm});

  final String label;

  /// The title and message to confirm with first, for an answer that moves
  /// screen time against what was decided before.
  final (String, String)? confirm;
}

/// One finished quest, with the parent's answer (PR-2).
///
/// A quest session shows its Before and After photos together, side by side
/// or swiped between on a narrow phone, and what the phone saw: the camera,
/// the minutes of real work, how much it looked like the chore and how much
/// the scene changed. A chore no model checks shows a Manual check banner and
/// no model figures. An older quest sent as one photo shows that photo and
/// what the automatic check made of it.
///
/// Approve and Send back are the same as ever and call the same decide
/// endpoint: nothing else here credits minutes.
class SubmissionReviewScreen extends ConsumerStatefulWidget {
  const SubmissionReviewScreen({super.key, required this.submission});

  final Submission submission;

  @override
  ConsumerState<SubmissionReviewScreen> createState() => _SubmissionReviewScreenState();
}

class _SubmissionReviewScreenState extends ConsumerState<SubmissionReviewScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _answer({required bool approve, (String, String)? confirm}) async {
    if (confirm != null) {
      final (title, message) = confirm;
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
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
      await ref.read(parentApiProvider).decide(widget.submission.id, approved: approve);
      if (mounted) _close(approve ? 'Approved: $chore.' : 'Sent back: $chore.');
    } on ApiRejected catch (e) {
      if (!mounted) return;
      // 409: decided differently on another phone first, or a quest whose
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
    final avatar = children.hasValue ? children.requireValue.where((c) => c.id == s.childId).firstOrNull?.avatar : null;
    final name = s.childName ?? 'Your child';
    final chore = s.choreName ?? 'Chore';
    final error = _error;

    const takeBack = (
      'Send it back?',
      "The screen time this chore earned will be taken away, and it can't be approved again.",
    );
    final give = ('Approve it?', '$name gets the screen time for this chore.');

    final (String question, _Answer? approve, _Answer? reject) = switch ((s.parentDecision, s.routing, s.isSession)) {
      (SubmissionStatus.approved, _, _) => (
          'You approved this quest.',
          null,
          const _Answer('Change to not done', confirm: takeBack),
        ),
      (SubmissionStatus.rejected, _, _) => (
          'You sent this quest back.',
          _Answer('Change to approved', confirm: give),
          null,
        ),
      (_, _, true) || (_, Routing.pendingReview, _) => (
          'Is the quest done?',
          const _Answer('Yes, approve'),
          const _Answer('No, send it back'),
        ),
      (_, Routing.autoApproved, false) => (
          'This photo was approved automatically and its screen time added. Is it right?',
          const _Answer("Yes, it's done"),
          const _Answer('No, send it back', confirm: takeBack),
        ),
      (_, Routing.autoRejected, false) => (
          'This photo was sent back automatically. Is it right?',
          _Answer("It's done, approve it", confirm: give),
          const _Answer("Right, it's not done"),
        ),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Check a quest')),
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
                      Text(chore, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        '$name · ${sentLabel(context, s.submittedAt)}',
                        style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (s.mode == SessionMode.manual) ...[
              _ManualBanner(submission: s),
              const SizedBox(height: 12),
            ],
            if (s.isSession && s.beforePhotoUrl != null)
              BeforeAfterPhotos(before: s.beforePhotoUrl!, after: s.photoUrl, chore: chore, name: name)
            else
              _OnePhoto(url: s.photoUrl, label: 'Photo of $chore from $name'),
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
                    if (s.mode == SessionMode.motion)
                      EvidencePanel(submission: s)
                    else if (s.mode == SessionMode.manual)
                      Text(
                        'Compare the Before and After photos and decide.',
                        style: text.bodyLarge,
                      )
                    else ...[
                      Text('Automatic check', style: text.labelLarge),
                      const SizedBox(height: 4),
                      Text(photoCheckLabel(s), style: text.bodyLarge),
                      if (isStandIn(s))
                        Text(
                          'From the test stand-in, not the trained model.',
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
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
                onPressed: _busy ? null : () => _answer(approve: true, confirm: approve.confirm),
                icon: const Icon(Icons.check_rounded),
                label: Text(approve.label),
              ),
            if (approve != null && reject != null) const SizedBox(height: 10),
            if (reject != null)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _answer(approve: false, confirm: reject.confirm),
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52)),
                icon: const Icon(Icons.undo_rounded),
                label: Text(reject.label),
              ),
          ],
        ),
      ),
    );
  }
}

/// No model watched this quest: why, and what that asks of the parent.
class _ManualBanner extends StatelessWidget {
  const _ManualBanner({required this.submission});

  final Submission submission;

  @override
  Widget build(BuildContext context) {
    final tint = QuestColors.of(context).saved;
    final text = Theme.of(context).textTheme;
    final why = (submission.evidence?.modelUnavailable ?? false)
        ? "The movement check couldn't run on the phone this time."
        : 'This chore is checked by you, not by movement.';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: tint.fill, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.visibility_rounded, color: tint.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Manual check', style: text.titleSmall?.copyWith(color: tint.ink, fontWeight: FontWeight.w700)),
                Text(why, style: text.bodyMedium?.copyWith(color: tint.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A quest session's Before and After photos together (PR-2): side by side,
/// or on a narrow phone one at a time with a swipe between them. A tap opens
/// both full screen, to zoom.
class BeforeAfterPhotos extends StatefulWidget {
  const BeforeAfterPhotos({
    super.key,
    required this.before,
    required this.after,
    required this.chore,
    required this.name,
  });

  final String before;
  final String after;
  final String chore;
  final String name;

  /// Narrower than this, the two photos are swiped between.
  static const sideBySideWidth = 300.0;

  @override
  State<BeforeAfterPhotos> createState() => _BeforeAfterPhotosState();
}

class _BeforeAfterPhotosState extends State<BeforeAfterPhotos> {
  var _page = 0;

  void _open(int start) => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _FullPhotos(
            photos: [(widget.before, 'Before'), (widget.after, 'After')],
            start: start,
            chore: widget.chore,
            name: widget.name,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= BeforeAfterPhotos.sideBySideWidth) {
          final tileWidth = (width - 10) / 2;
          return Row(
            children: [
              SizedBox(width: tileWidth, child: _photoTile(widget.before, 'Before', 0, tileWidth)),
              const SizedBox(width: 10),
              SizedBox(width: tileWidth, child: _photoTile(widget.after, 'After', 1, tileWidth)),
            ],
          );
        }

        final height = math.min(width * 4 / 3, MediaQuery.sizeOf(context).height * 0.5);
        return Column(
          children: [
            SizedBox(
              height: height,
              child: PageView(
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  _photoTile(widget.before, 'Before', 0, width),
                  _photoTile(widget.after, 'After', 1, width),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Text(
                _page == 0 ? 'Before · swipe to see After' : 'After · swipe back to see Before',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _photoTile(String url, String which, int index, double width) {
    final label = '$which photo of ${widget.chore} from ${widget.name}';
    // The tile carries its own name, so a photo that fails to load is still
    // "Before photo of ..." to a screen reader, not a nameless button.
    return Semantics(
      label: label,
      button: true,
      hint: 'Opens the photos full screen',
      excludeSemantics: true,
      onTap: () => _open(index),
      child: GestureDetector(
        onTap: () => _open(index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ColoredBox(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SubmissionPhoto(url: url, fit: BoxFit.contain, semanticLabel: label),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _PhotoLabel(which),
                  ),
                  const Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.zoom_in_rounded, color: Colors.white, size: 20),
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
  }
}

class _PhotoLabel extends StatelessWidget {
  const _PhotoLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// What the phone saw during a motion-checked session (PR-2): the camera,
/// the minutes of real work out of the whole session, how much it looked
/// like the chore, how much the scene changed, and short flags.
class EvidencePanel extends StatelessWidget {
  const EvidencePanel({super.key, required this.submission});

  final Submission submission;

  @override
  Widget build(BuildContext context) {
    final s = submission;
    final e = s.evidence;
    final text = Theme.of(context).textTheme;
    final active = s.activeSeconds ?? e?.activeSeconds;
    final total = e?.sessionSeconds;
    final probability = s.modelConfidence ?? e?.meanProbability;
    final scene = e?.sceneChange;
    final flags = evidenceFlags(s);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What the phone saw', style: text.labelLarge),
        const SizedBox(height: 8),
        _Fact(icon: Icons.videocam_rounded, label: 'Camera', value: cameraLabel(e?.camera)),
        if (active != null)
          _Fact(
            icon: Icons.timer_rounded,
            label: 'Real work',
            value: total == null ? formatDuration(active) : '${formatDuration(active)} of ${formatDuration(total)}',
          ),
        if (probability != null) ...[
          const SizedBox(height: 6),
          _Bar(label: 'Looked like ${s.choreName ?? 'the chore'}', value: probability),
        ],
        if (scene != null) ...[
          const SizedBox(height: 6),
          _Bar(label: 'Changed between Before and After', value: scene.clamp(0, 1).toDouble()),
        ],
        if (flags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final flag in flags) _Flag(flag)],
          ),
        ],
      ],
    );
  }
}

/// "Phone, back camera", "Phone, front camera", "Third-party camera".
String cameraLabel(String? camera) => switch (camera) {
      'phone_back' => 'Phone, back camera',
      'phone_front' => 'Phone, front camera',
      'external' || 'network' => 'Third-party camera',
      _ => 'Phone camera',
    };

/// "45 s", "1 min 10 s", "3 min".
String formatDuration(int seconds) {
  if (seconds < 60) return '$seconds s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return rest == 0 ? '$minutes min' : '$minutes min $rest s';
}

/// Short notes on a session worth the parent's attention, in plain words.
List<String> evidenceFlags(Submission s) {
  final e = s.evidence;
  if (e == null) return const [];
  return [
    if (e.cameraFlipped) 'Camera was flipped',
    if ((e.sessionSeconds ?? 60) < 60) 'Very short session',
    if (e.cameraFallback) "The third-party camera wasn't connected",
    if (e.sceneFits == false) "The room doesn't look like this chore's place",
  ];
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                TextSpan(text: value),
              ]),
              style: text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple bar from 0 to 100%, with its figure in words beside the label.
class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Its own node, so it is read as one figure rather than run into the
    // panel around it.
    return Semantics(
      container: true,
      label: '$label: ${formatPercent(value)}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: text.bodyMedium)),
                Text(formatPercent(value), style: text.labelLarge),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: value, minHeight: 8),
            ),
          ],
        ),
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final tint = QuestColors.of(context).review;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: tint.fill, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: tint.ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: tint.ink, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// An older quest's one photo, large; a tap opens it full screen.
class _OnePhoto extends StatelessWidget {
  const _OnePhoto({required this.url, required this.label});

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Big enough to judge the chore, short enough to leave the answer in
        // reach without scrolling on most phones.
        final height = math.min(constraints.maxWidth * 4 / 3, MediaQuery.sizeOf(context).height * 0.55);
        // Zooming happens on a screen of its own: a pinch inside this
        // scrolling list would fight the list for the same gesture.
        return Semantics(
          button: true,
          hint: 'Opens the photo full screen',
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => _FullPhotos(photos: [(url, 'Photo')], start: 0, chore: '', name: ''),
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
                      SubmissionPhoto(url: url, fit: BoxFit.contain, semanticLabel: label),
                      const Positioned(
                        right: 10,
                        bottom: 10,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.zoom_in_rounded, color: Colors.white),
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
    );
  }
}

/// The photos alone, for a closer look: pinch to zoom, drag to move around,
/// swipe between Before and After.
class _FullPhotos extends StatelessWidget {
  const _FullPhotos({required this.photos, required this.start, required this.chore, required this.name});

  final List<(String, String)> photos;
  final int start;
  final String chore;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(photos.length == 1 ? 'Photo' : 'Before and After'),
      ),
      body: PageView(
        controller: PageController(initialPage: start),
        children: [
          for (final (url, which) in photos)
            Stack(
              children: [
                InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: SubmissionPhoto(
                      url: url,
                      fit: BoxFit.contain,
                      semanticLabel: chore.isEmpty ? which : '$which photo of $chore from $name',
                    ),
                  ),
                ),
                if (photos.length > 1) Positioned(left: 12, top: 12, child: _PhotoLabel(which)),
              ],
            ),
        ],
      ),
    );
  }
}
