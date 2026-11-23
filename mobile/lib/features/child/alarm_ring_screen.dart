import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/alarm/alarm_safety_net.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/chore.dart';
import '../../shared/chore_icons.dart';
import '../../shared/theme.dart';
import 'live_camera_screen.dart';
import 'quest_session_providers.dart';

/// The page a ringing quest alarm opens, over the lock screen too (DV-5):
/// the quest and one big Start the quest button, which goes straight into
/// the live session with the alarm still ringing. The back button does
/// nothing, and nothing here looks like a way out.
///
/// The safety net (DV-7) is here as well, kept small: a grown-up stop that
/// needs the parent's own password, and in debug builds a skip.
class AlarmRingScreen extends ConsumerStatefulWidget {
  const AlarmRingScreen({super.key, required this.assignment, required this.ringingSince});

  final Assignment assignment;
  final DateTime ringingSince;

  @override
  ConsumerState<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends ConsumerState<AlarmRingScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _start() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => QuestSessionScreen(assignment: widget.assignment)),
    );
  }

  Future<void> _grownUpStop() async {
    final stopped = await showDialog<bool>(
      context: context,
      builder: (_) => _GrownUpStopDialog(assignment: widget.assignment, net: ref.read(alarmSafetyNetProvider)),
    );
    if (stopped == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final chore = widget.assignment.chore;
    final ringing = DateTime.now().difference(widget.ringingSince);
    final minutes = ringing.inMinutes;
    final colors = QuestColors.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colors.header.first,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.alarm_rounded, size: 72, color: Colors.white),
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Time for a quest!',
                      textAlign: TextAlign.center,
                      style: text.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    minutes == 0 ? 'Ringing now' : 'Ringing for $minutes min',
                    textAlign: TextAlign.center,
                    style: text.bodyLarge?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          ChoreIcon(icon: chore.icon, category: chore.category, size: 56),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(chore.name, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _start,
                    // White on the green: the one thing on the page to find.
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: colors.header.first,
                      minimumSize: const Size(64, 72),
                      textStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 32),
                    label: const Text('Start the quest'),
                  ),
                  const SizedBox(height: 40),
                  TextButton(
                    onPressed: _grownUpStop,
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    child: const Text('Grown-up stop'),
                  ),
                  if (kDebugMode)
                    TextButton(
                      onPressed: () async {
                        await ref.read(questAlarmServiceProvider).stop(widget.assignment);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      style: TextButton.styleFrom(foregroundColor: Colors.white54),
                      child: const Text('Test build: skip'),
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

/// The parent types their account password on the child's phone; the
/// server checks it and records the stop (BE-10). A wrong one changes
/// nothing.
class _GrownUpStopDialog extends StatefulWidget {
  const _GrownUpStopDialog({required this.assignment, required this.net});

  final Assignment assignment;
  final AlarmSafetyNet net;

  @override
  State<_GrownUpStopDialog> createState() => _GrownUpStopDialogState();
}

class _GrownUpStopDialogState extends State<_GrownUpStopDialog> {
  final _password = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _stop() async {
    if (_password.text.isEmpty) {
      setState(() => _error = "Type the grown-up's password.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.net.grownUpStop(widget.assignment, _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiRejected catch (e) {
      if (mounted) setState(() => _error = e.errorFor('password') ?? e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Large text on a small phone, with the keyboard up, is taller than
      // the screen.
      scrollable: true,
      title: const Text('Grown-up stop'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('For a grown-up: your ChoreQuest password stops this alarm. You will see that it was stopped.'),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            enabled: !_busy,
            decoration: InputDecoration(labelText: 'Password', errorText: _error),
            onSubmitted: (_) => _stop(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _stop, child: const Text('Stop the alarm')),
      ],
    );
  }
}
