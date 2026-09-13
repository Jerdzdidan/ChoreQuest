import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/chore.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../core/uploads/client_token.dart';
import '../../core/verification/chore_verifier.dart';
import 'child_providers.dart';
import 'chore_camera_screen.dart';
import 'submission_result_screen.dart';
import 'submission_sender.dart';

/// The photo just taken, with two choices: send it, or take it again.
class ConfirmPhotoScreen extends ConsumerStatefulWidget {
  const ConfirmPhotoScreen({
    super.key,
    required this.assignment,
    required this.photoPath,
  });

  final Assignment assignment;
  final String photoPath;

  @override
  ConsumerState<ConfirmPhotoScreen> createState() => _ConfirmPhotoScreenState();
}

class _ConfirmPhotoScreenState extends ConsumerState<ConfirmPhotoScreen> {
  /// One token for this photo, kept by the queue through every retry.
  final String _token = newClientToken();
  bool _sending = false;

  void _discardPhoto() {
    try {
      File(widget.photoPath).deleteSync();
    } catch (_) {
      // Already gone. Nothing to tidy.
    }
  }

  void _retake() {
    _discardPhoto();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChoreCameraScreen(assignment: widget.assignment),
      ),
    );
  }

  Future<void> _send() async {
    final me = switch (ref.read(sessionProvider)) {
      AsyncData(value: final ChildSession session) => session,
      _ => null,
    };
    if (me == null) return;
    setState(() => _sending = true);

    final verdict = await ref
        .read(choreVerifierProvider)
        .verify(photoPath: widget.photoPath, chore: widget.assignment.chore);
    if (!mounted) return;

    final outcome = await queueAndSend(
      queue: ref.read(uploadQueueProvider),
      sync: ref.read(uploadSyncProvider(me.token)),
      childId: me.id,
      assignment: widget.assignment,
      photoPath: widget.photoPath,
      clientToken: _token,
      verdict: verdict,
    );

    // The queue keeps its own copy for as long as the photo might still need
    // sending, so the camera's file goes now: a photo of the inside of a home
    // is not left lying in a cache.
    _discardPhoto();
    if (!mounted) return;
    refreshChildData(ref);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SubmissionResultScreen(
          assignment: widget.assignment,
          outcome: outcome,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final showTestControl = kDebugMode && widget.assignment.chore.modelVerifiable;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Image.file(
                  File(widget.photoPath),
                  fit: BoxFit.contain,
                  // Decode at screen size, not camera size: a full-resolution
                  // photo held in memory is a crash waiting on a low-end phone.
                  cacheWidth: (media.size.width * media.devicePixelRatio).round(),
                  errorBuilder: (context, error, stack) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              ),
            ),
            if (showTestControl) const _StubOutcomeChooser(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: _BigChoice(
                      icon: Icons.replay_rounded,
                      label: 'Take again',
                      background: Colors.white24,
                      foreground: Colors.white,
                      onTap: _sending ? null : _retake,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _BigChoice(
                      icon: Icons.send_rounded,
                      label: 'Send',
                      background: const Color(0xFF2E7D32),
                      foreground: Colors.white,
                      busy: _sending,
                      onTap: _sending ? null : _send,
                    ),
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

class _BigChoice extends StatelessWidget {
  const _BigChoice({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox.square(
                  dimension: 40,
                  child: CircularProgressIndicator(color: foreground),
                )
              else
                Icon(icon, size: 40, color: foreground),
              const SizedBox(height: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Debug builds only. Lets a tester choose what the stand-in checker reports,
/// so all three routes can be seen before the real model exists.
class _StubOutcomeChooser extends ConsumerStatefulWidget {
  const _StubOutcomeChooser();

  @override
  ConsumerState<_StubOutcomeChooser> createState() => _StubOutcomeChooserState();
}

class _StubOutcomeChooserState extends ConsumerState<_StubOutcomeChooser> {
  @override
  Widget build(BuildContext context) {
    final verifier = ref.watch(choreVerifierProvider);
    if (verifier is! StubVerifier) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3D6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            'Test build only: pretend checker result',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          SegmentedButton<StubOutcome>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: StubOutcome.likelyDone, label: Text('Done 95%')),
              ButtonSegment(value: StubOutcome.unsure, label: Text('Unsure 60%')),
              ButtonSegment(value: StubOutcome.likelyNotDone, label: Text('Not done 95%')),
            ],
            selected: {verifier.outcome},
            onSelectionChanged: (selection) =>
                setState(() => verifier.outcome = selection.first),
          ),
        ],
      ),
    );
  }
}
