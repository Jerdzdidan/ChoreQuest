import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/models/chore.dart';
import '../../shared/chore_icons.dart';
import 'confirm_photo_screen.dart';

/// A full-screen camera with one large button.
class ChoreCameraScreen extends StatefulWidget {
  const ChoreCameraScreen({super.key, required this.assignment});

  final Assignment assignment;

  @override
  State<ChoreCameraScreen> createState() => _ChoreCameraScreenState();
}

enum _Problem { denied, noCamera, failed }

class _ChoreCameraScreenState extends State<ChoreCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  _Problem? _problem;
  bool _starting = false;
  bool _capturing = false;
  bool _releasedForBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  /// The plugin no longer manages the camera across app switches. Release it
  /// when the app is backgrounded and take it back on return, or the preview
  /// freezes and the camera stays locked to this app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;

    if (state == AppLifecycleState.inactive) {
      // Not running yet: this is most likely the permission prompt itself,
      // and tearing the camera down here would ask again in an endless loop.
      if (controller == null || !controller.value.isInitialized) return;
      _controller = null;
      _releasedForBackground = true;
      controller.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _releasedForBackground) {
      _releasedForBackground = false;
      _start();
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _problem = null;
    });

    CameraController? created;
    try {
      // If the camera service never answers, give up after ten seconds and
      // offer "Try again" instead of a spinner that never ends. Only finding
      // the cameras is timed: opening one can legitimately wait on a parent
      // reading the permission prompt.
      final cameras =
          await availableCameras().timeout(const Duration(seconds: 10));
      if (cameras.isEmpty) {
        if (mounted) setState(() => _problem = _Problem.noCamera);
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // No audio: a photograph needs none, and a microphone prompt would only
      // puzzle the parent reading it.
      created = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await created.initialize();

      if (!mounted) {
        await created.dispose();
        return;
      }
      setState(() => _controller = created);
    } on CameraException catch (e) {
      await created?.dispose();
      if (mounted) {
        setState(
          () => _problem =
              e.code == 'CameraAccessDenied' ? _Problem.denied : _Problem.failed,
        );
      }
    } catch (_) {
      await created?.dispose();
      if (mounted) setState(() => _problem = _Problem.failed);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }

    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      if (!mounted) return;
      // Replacing this screen releases the camera while the child looks at
      // the photo, which matters on a phone with little memory.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ConfirmPhotoScreen(
            assignment: widget.assignment,
            photoPath: shot.path,
          ),
        ),
      );
    } on CameraException {
      if (mounted) setState(() => _problem = _Problem.failed);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final problem = _problem;
    final chore = widget.assignment.chore;
    final ready = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: ready
                    ? CameraPreview(controller)
                    : problem != null
                        ? _ProblemPanel(problem: problem, onRetry: _start)
                        : const CircularProgressIndicator(color: Colors.white),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton.filledTonal(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Positioned(
              top: 12,
              left: 64,
              right: 16,
              child: Row(
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
            ),
            if (ready)
              Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: Center(
                  child: _ShutterButton(busy: _capturing, onPressed: _capture),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Take the photo',
      child: GestureDetector(
        onTap: busy ? null : onPressed,
        child: Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 6),
          ),
          padding: const EdgeInsets.all(6),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: busy ? Colors.white54 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProblemPanel extends StatelessWidget {
  const _ProblemPanel({required this.problem, required this.onRetry});

  final _Problem problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (icon, title, message) = switch (problem) {
      _Problem.denied => (
          Icons.no_photography_outlined,
          "The camera isn't allowed yet",
          'Ask a grown-up to allow it: open Settings, then Apps, ChoreQuest, '
              'Permissions, and turn on Camera.',
        ),
      _Problem.noCamera => (
          Icons.videocam_off_outlined,
          'No camera found',
          'This phone has no camera ChoreQuest can use.',
        ),
      _Problem.failed => (
          Icons.error_outline,
          "The camera didn't start",
          'Close any other app using the camera, then try again.',
        ),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.white),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: Colors.white70),
          ),
          if (problem != _Problem.noCamera) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}
