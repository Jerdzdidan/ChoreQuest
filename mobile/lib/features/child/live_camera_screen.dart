import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/models/chore.dart';
import '../../core/quest_session/fake_detector.dart';
import '../../core/quest_session/frame_prep.dart';
import '../../core/quest_session/model_config.dart';
import '../../core/quest_session/quest_session.dart';
import '../../shared/chore_icons.dart';
import '../../shared/strap.dart';
import 'child_providers.dart';
import 'quest_session_controller.dart';
import 'quest_session_providers.dart';
import 'submission_result_screen.dart';

/// The live quest session (LS-2): the camera, the child doing the chore, and
/// a Done button that is not on the screen at all until there has been
/// enough movement that looks like it.
///
/// Opening this screen is tapping Start the quest. The screen stays awake,
/// upright and silent (no microphone is ever asked for), lets go of the
/// camera when the app goes to the background and takes it back on return.
/// The phone's back camera watches, worn on a head or chest strap so it sees
/// the child's hands (CAM-3); before a quest the model checks, the child is
/// asked to strap the phone on.
///
/// The words stay encouraging throughout: the child never sees a score or a
/// failure message.
class QuestSessionScreen extends ConsumerStatefulWidget {
  const QuestSessionScreen({super.key, required this.assignment});

  final Assignment assignment;

  @override
  ConsumerState<QuestSessionScreen> createState() => _QuestSessionScreenState();
}

class _QuestSessionScreenState extends ConsumerState<QuestSessionScreen> with WidgetsBindingObserver {
  QuestSessionController? _controller;
  bool _leaving = false;

  /// A quest the model checks asks first whether the phone is strapped on;
  /// null until the child answers (CAM-3).
  bool? _strapped;

  bool get _modelChecks {
    final chore = widget.assignment.chore;
    return chore.verificationMode == VerificationMode.motion && chore.modelClass != null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    unawaited(WakelockPlus.enable().catchError((_) {}));
    if (!_modelChecks) unawaited(_start());
  }

  /// The child answered the strap question. The alarm keeps ringing while
  /// they strap the phone on.
  void _answer(bool strapped) {
    if (_strapped != null) return;
    setState(() => _strapped = strapped);
    unawaited(_start(strapped: strapped));
  }

  Future<void> _start({bool strapped = true}) async {
    ModelConfig config;
    try {
      config = await ref.read(modelConfigProvider.future);
    } catch (_) {
      config = ModelConfig.fallback;
    }
    // The model files load once, at the first session; until then there is
    // no detector to hand out. A load that never finishes counts as no model.
    try {
      await ref.read(lstmModelsProvider.future).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Missing, broken or stuck: the session runs manual.
    }
    if (!mounted) return;
    final chore = widget.assignment.chore;
    final detector = ref.read(choreDetectorProvider)();
    FramePrepWorker? prep;
    if (detector.available && detector.needsFrames) {
      prep = FramePrepWorker(size: ((config.json['model'] as Map?)?['input_size'] as num? ?? 192).toInt());
      await prep.start();
    }
    if (!mounted) {
      prep?.stop();
      return;
    }
    final stopAlarm = ref.read(alarmStopperProvider);
    final controller = QuestSessionController(
      assignment: widget.assignment,
      camera: ref.read(sessionCameraProvider)(widget.assignment),
      detector: detector,
      thresholds: config.thresholdsFor(chore.key, catalogueMinSeconds: chore.minActiveSeconds),
      sendPackage: ref.read(sessionSenderProvider),
      onStopAlarm: () => stopAlarm(widget.assignment),
      prep: prep,
      strapped: strapped,
    )..addListener(_onChange);
    setState(() => _controller = controller);
    await controller.begin();
  }

  void _onChange() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (controller.state == SessionState.sent || (controller.state == SessionState.failed && controller.outcome != null)) {
      _finish(controller);
    }
    setState(() {});
  }

  /// Sent (or queued, or turned down): on to the result, which says so
  /// gently; the celebration waits for the grown-up's yes (LS-10).
  void _finish(QuestSessionController controller) {
    final outcome = controller.outcome;
    if (_leaving || outcome == null) return;
    _leaving = true;
    refreshChildData(ref);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SubmissionResultScreen(assignment: widget.assignment, outcome: outcome, fromSession: true),
        ),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null) return;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Not open yet: this is most likely the permission prompt itself, and
      // letting go here would ask again in a loop.
      if (!controller.camera.isOpen) return;
      unawaited(controller.pause());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(controller.resume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller
      ?..removeListener(_onChange)
      ..dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    unawaited(WakelockPlus.disable().catchError((_) {}));
    super.dispose();
  }

  Future<void> _close() async {
    final controller = _controller;
    final midway = controller != null &&
        controller.state != SessionState.sent &&
        controller.state != SessionState.failed &&
        controller.state != SessionState.idle;
    if (midway) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stop this quest?'),
          content: const Text("You can start it again later. Nothing you've done is lost if you send it first."),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep going')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Stop')),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final chore = widget.assignment.chore;
    final reviewing = controller != null &&
        (controller.state == SessionState.reviewing || controller.state == SessionState.sending);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: controller == null
                    ? (_modelChecks && _strapped == null
                        ? _StrapStep(onAnswer: _answer)
                        : const Center(child: CircularProgressIndicator(color: Colors.white)))
                    : reviewing
                        ? _Review(controller: controller)
                        : controller.problem != null
                            ? _ProblemPanel(problem: controller.problem!, onRetry: controller.retryCamera)
                            : Center(child: controller.camera.preview()),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton.filledTonal(
                  tooltip: 'Close',
                  onPressed: _close,
                  icon: const Icon(Icons.close),
                ),
              ),
              Positioned(
                top: 12,
                left: 64,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ChoreIcon(icon: chore.icon, category: chore.category, size: 40),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            chore.name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  shadows: const [Shadow(blurRadius: 6)],
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (controller != null && !reviewing && controller.problem == null)
                Positioned(left: 0, right: 0, bottom: 0, child: _SessionBar(controller: controller)),
              if (kDebugMode && controller != null && controller.detector is FakeDetector && !reviewing)
                Positioned(top: 64, right: 8, child: _FakePanel(detector: controller.detector as FakeDetector)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Before a quest the model checks (CAM-3): the phone goes on a head or
/// chest strap, so the back camera sees the child's hands. Without one the
/// quest still goes ahead, and the grown-up judges from the photos.
class _StrapStep extends StatelessWidget {
  const _StrapStep({required this.onAnswer});

  final void Function(bool strapped) onAnswer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // A card on the camera's dark backdrop, below the quest's name, which is
    // drawn in white for the camera.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Strap on your phone so it can see your hands',
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 20),
              const StrapPictures(size: 110),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => onAnswer(true),
                style: FilledButton.styleFrom(minimumSize: const Size(64, 64)),
                icon: const Icon(Icons.check_rounded),
                label: const Text('My phone is strapped on'),
              ),
              const SizedBox(height: 20),
              Text(
                'No strap? You can still do your quest. Your grown-up will check your Before and After photos.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              TextButton(onPressed: () => onAnswer(false), child: const Text('Start without a strap')),
            ],
          ),
        ),
      ),
    );
  }
}

/// The message, the progress ring and the buttons along the bottom.
class _SessionBar extends StatelessWidget {
  const _SessionBar({required this.controller});

  final QuestSessionController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = controller.state;
    final manual = controller.session.mode == CheckMode.manual;
    final message = switch (state) {
      SessionState.idle || SessionState.ringing || SessionState.starting =>
        controller.beforePath == null ? 'Hold the phone still for your Before photo' : 'Got it!',
      SessionState.waitingForMovement => 'Show me your quest!',
      SessionState.active => 'Keep going — I can see you!',
      SessionState.doneAvailable =>
        manual ? 'Do your quest, then tap Done.' : "Great job! Tap Done when you're finished.",
      SessionState.capturingAfter => 'Hold still for your After photo',
      _ => '',
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 64),
                const SizedBox(width: 16),
                SizedBox.square(
                  dimension: 96,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!manual && state != SessionState.capturingAfter)
                        Semantics(
                          label: 'How far along you are',
                          value: '${(controller.progress * 100).round()}%',
                          child: SizedBox.square(
                            dimension: 96,
                            child: CircularProgressIndicator(
                              value: controller.progress,
                              strokeWidth: 8,
                              color: Colors.white,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ),
                      // Not in the tree at all before Done is available (LS-6).
                      if (controller.session.showsDone)
                        SizedBox.square(
                          dimension: 80,
                          child: FilledButton(
                            onPressed: controller.busy ? null : controller.done,
                            style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                            child: const Text('Done', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Before and After side by side, with Send to my grown-up (LS-7, LS-9).
class _Review extends StatelessWidget {
  const _Review({required this.controller});

  final QuestSessionController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sending = controller.state == SessionState.sending;

    Widget photo(String? path, String label) => Expanded(
          child: Column(
            children: [
              Text(label, style: text.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              AspectRatio(
                aspectRatio: 3 / 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: path == null
                      ? const ColoredBox(color: Colors.white12)
                      : Image.file(File(path), fit: BoxFit.cover, semanticLabel: '$label photo',
                          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.white12)),
                ),
              ),
            ],
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 72, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Look at what you did!',
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              photo(controller.beforePath, 'Before'),
              const SizedBox(width: 12),
              photo(controller.afterPath, 'After'),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: sending || controller.busy ? null : controller.send,
            style: FilledButton.styleFrom(minimumSize: const Size(64, 56)),
            icon: sending
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: const Text('Send to my grown-up'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: sending || controller.busy ? null : controller.retakeAfter,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Take the After photo again'),
          ),
        ],
      ),
    );
  }
}

/// Debug builds only: what the fake detector pretends (LS-4).
class _FakePanel extends StatefulWidget {
  const _FakePanel({required this.detector});

  final FakeDetector detector;

  @override
  State<_FakePanel> createState() => _FakePanelState();
}

class _FakePanelState extends State<_FakePanel> {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('Test: pretend', style: TextStyle(color: Colors.white70, fontSize: 11)),
            for (final (behaviour, label) in const [
              (FakeBehaviour.idle, 'Still'),
              (FakeBehaviour.doingTheChore, 'The chore'),
              (FakeBehaviour.somethingElse, 'Other moves'),
            ])
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text(label),
                selected: widget.detector.behaviour == behaviour,
                onSelected: (_) => setState(() => widget.detector.behaviour = behaviour),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProblemPanel extends StatelessWidget {
  const _ProblemPanel({required this.problem, required this.onRetry});

  final CameraProblem problem;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (icon, title, message) = switch (problem) {
      CameraProblem.denied => (
          Icons.no_photography_outlined,
          "The camera isn't allowed yet",
          'Ask a grown-up to allow it: open Settings, then Apps, ChoreQuest, Permissions, and turn on Camera.',
        ),
      CameraProblem.noCamera => (
          Icons.videocam_off_outlined,
          'No camera found',
          'This phone has no camera ChoreQuest can use.',
        ),
      CameraProblem.failed => (
          Icons.error_outline,
          "The camera didn't start",
          'Close any other app using the camera, then try again.',
        ),
    };

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.white),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: text.headlineSmall?.copyWith(color: Colors.white)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: text.bodyLarge?.copyWith(color: Colors.white70)),
            if (problem != CameraProblem.noCamera) ...[
              const SizedBox(height: 24),
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
