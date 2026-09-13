import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/balance.dart';
import '../../shared/format.dart';
import '../../shared/inline_error.dart';
import 'child_providers.dart';

Future<void> showScreenTimeSheet(BuildContext context, Balance balance) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _ScreenTimeSheet(balance: balance),
  );
}

/// Choose how much screen time to use now.
///
/// The minutes are taken from the ledger when the timer starts, on the server,
/// so the balance can never be spent twice from two phones. ChoreQuest does
/// not lock other apps (a stated limitation of the study); the timer is there
/// for the child and the parent to see.
class _ScreenTimeSheet extends ConsumerStatefulWidget {
  const _ScreenTimeSheet({required this.balance});

  final Balance balance;

  @override
  ConsumerState<_ScreenTimeSheet> createState() => _ScreenTimeSheetState();
}

class _ScreenTimeSheetState extends ConsumerState<_ScreenTimeSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _use(int minutes) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(childApiProvider).consume(minutes);
      ref.invalidate(balanceProvider);
      if (!mounted) return;

      final navigator = Navigator.of(context);
      navigator.pop();
      if (result.consumedMinutes > 0) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => CountdownScreen(
              minutes: result.consumedMinutes,
              endsAt: DateTime.now().add(Duration(minutes: result.consumedMinutes)),
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final spendable = widget.balance.spendableMinutes;
    final options = [5, 10, 15, 30, 60].where((m) => m <= spendable).toList();
    final error = _error;

    // Scrolls rather than overflowing when a small phone's text is enlarged.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('How much screen time?', style: text.headlineSmall),
          const SizedBox(height: 4),
          Text('You have ${formatMinutes(spendable)}.', style: text.titleMedium),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (final minutes in options)
                _TimeChoice(
                  label: formatMinutes(minutes),
                  onTap: _busy ? null : () => _use(minutes),
                ),
              if (spendable > 0 && !options.contains(spendable))
                _TimeChoice(
                  label: 'All ${formatMinutes(spendable)}',
                  onTap: _busy ? null : () => _use(spendable),
                ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            InlineError(error),
          ],
          const SizedBox(height: 16),
          Text(
            'The timer starts straight away. Stopping early does not give the '
            'minutes back.',
            textAlign: TextAlign.center,
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TimeChoice extends StatelessWidget {
  const _TimeChoice({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minWidth: 96, minHeight: 72),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}

/// A countdown for screen time already taken from the balance.
///
/// Worked out from the end time rather than by counting ticks, so it stays
/// right after the child switches to another app and comes back.
class CountdownScreen extends StatefulWidget {
  const CountdownScreen({super.key, required this.minutes, required this.endsAt});

  final int minutes;
  final DateTime endsAt;

  @override
  State<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> {
  late final Timer _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
    if (!mounted) return;
    setState(() {});
    if (!DateTime.now().isBefore(widget.endsAt)) _ticker.cancel();
  });

  @override
  void initState() {
    super.initState();
    _ticker; // start ticking
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  Future<void> _stopEarly() async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop now?'),
        content: const Text("The minutes you haven't used are not given back."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (stop == true && mounted) Navigator.of(context).pop();
  }

  static String _clock(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = widget.minutes * 60;
    final left = widget.endsAt.difference(DateTime.now()).inSeconds.clamp(0, total);
    final finished = left == 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Screen time')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: total == 0 ? 0 : left / total,
                        strokeWidth: 14,
                      ),
                    ),
                    Semantics(
                      liveRegion: finished,
                      child: Text(
                        finished ? "Time's up!" : _clock(left),
                        textAlign: TextAlign.center,
                        style: text.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                finished ? 'Time to put the screen away.' : 'Enjoy your screen time!',
                textAlign: TextAlign.center,
                style: text.titleLarge,
              ),
              const SizedBox(height: 24),
              if (finished)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to my chores'),
                )
              else
                OutlinedButton(
                  onPressed: _stopEarly,
                  child: const Text('Stop early'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
