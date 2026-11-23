import 'dart:convert';
import 'dart:io';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_files.dart';
import '../../core/models/submission.dart';
import '../../shared/theme.dart';

/// Which approvals each child on this phone has already been shown a
/// celebration for, so every approval is celebrated exactly once (LS-10),
/// however often the list is fetched and whichever child signs in.
class CelebrationLedger {
  CelebrationLedger(this.file);

  final File file;

  Future<Map<String, List<int>>> _read() async {
    try {
      if (!await file.exists()) return {};
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return {for (final MapEntry(:key, :value) in raw.entries) key: [for (final id in value as List) id as int]};
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, List<int>> all) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(all), flush: true);
    await temp.rename(file.path);
  }

  /// The approvals in [mine] this child has not been shown yet, and from now
  /// on counted as shown. The very first look for a child only takes note:
  /// approvals from before this phone knew them are not celebrated again.
  Future<List<Submission>> takeFresh(int childId, List<Submission> mine) async {
    final all = await _read();
    final approved = [for (final s in mine) if (s.status == SubmissionStatus.approved) s];
    final key = '$childId';
    final seen = all[key];
    all[key] = {...?seen, for (final s in approved) s.id}.toList();
    await _write(all);
    if (seen == null) return const [];
    return [for (final s in approved) if (!seen.contains(s.id)) s];
  }
}

final celebrationLedgerProvider = Provider<CelebrationLedger>(
  (ref) => CelebrationLedger(appFile(ref.watch(appFilesProvider), 'celebrated.json')),
);

/// The celebration for quests a grown-up has just said yes to: confetti, the
/// quests by name, and the reward (LS-10). Not shown when the quest was sent;
/// only now.
Future<void> showApprovalCelebration(BuildContext context, List<Submission> approved) {
  return showDialog<void>(
    context: context,
    builder: (context) => _CelebrationDialog(approved: approved),
  );
}

class _CelebrationDialog extends StatefulWidget {
  const _CelebrationDialog({required this.approved});

  final List<Submission> approved;

  @override
  State<_CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<_CelebrationDialog> {
  final _confetti = ConfettiController(duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !MediaQuery.of(context).disableAnimations) _confetti.play();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = QuestColors.of(context);
    final names = [for (final s in widget.approved) s.choreName ?? 'your quest'];
    final line = names.length == 1
        ? 'A grown-up said yes to ${names.single}!'
        : 'A grown-up said yes to ${names.length} of your quests!';

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        AlertDialog(
          icon: Icon(Icons.celebration_rounded, size: 56, color: colors.done),
          title: const Text('Hooray!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(liveRegion: true, child: Text(line, textAlign: TextAlign.center, style: text.titleMedium)),
              if (names.length > 1) ...[
                const SizedBox(height: 8),
                for (final name in names) Text(name, textAlign: TextAlign.center, style: text.bodyMedium),
              ],
              const SizedBox(height: 12),
              Text(
                'Your XP and screen time went up.',
                textAlign: TextAlign.center,
                style: text.titleSmall?.copyWith(color: colors.done, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Yay!')),
          ],
        ),
        IgnorePointer(
          child: ExcludeSemantics(
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.1,
              numberOfParticles: 16,
              gravity: 0.3,
              colors: colors.confetti,
            ),
          ),
        ),
      ],
    );
  }
}
