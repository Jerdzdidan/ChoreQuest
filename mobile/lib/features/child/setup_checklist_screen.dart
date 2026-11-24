import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/device/phone_readiness.dart';
import '../../shared/strap.dart';
import '../../shared/theme.dart';
import 'model_benchmark_screen.dart';
import 'quest_session_providers.dart';

/// "Ready for alarms" (DV-1), on the child's phone, for the grown-up setting
/// it up: what quest alarms need, each row green or red, and one tap that
/// opens the system screen fixing it. Shown the first time the app opens on
/// this phone, and from the home whenever a row is red. Checked again on
/// every return from Settings, and each check is reported to the server
/// (DV-10).
///
/// The last row is the strap (CAM-3): a picture of each kind and the
/// neck-cord warning, unticked until a grown-up says one is ready.
class SetupChecklistScreen extends ConsumerStatefulWidget {
  const SetupChecklistScreen({super.key, this.initial});

  /// The last check, shown while the next one runs.
  final ReadinessResult? initial;

  @override
  ConsumerState<SetupChecklistScreen> createState() => _SetupChecklistScreenState();
}

class _SetupChecklistScreenState extends ConsumerState<SetupChecklistScreen> with WidgetsBindingObserver {
  ReadinessResult? _result;
  var _checked = false;
  ReadinessRow? _fixing;
  var _openingMaker = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _result = widget.initial;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from a settings screen: see what changed.
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final outcome = await ref.read(phoneReadinessProvider).refresh();
    if (!mounted) return;
    setState(() {
      _checked = true;
      if (outcome != null) _result = outcome.result;
    });
  }

  Future<void> _fix(ReadinessRow row) async {
    if (row == ReadinessRow.strap) return _confirmStrap();
    setState(() {
      _fixing = row;
      _note = null;
    });
    final outcome = await ref.read(readinessProbeProvider).fix(row);
    if (!mounted) return;
    setState(() {
      _fixing = null;
      _note = switch (outcome) {
        FixOutcome.unavailable => 'This phone has no shortcut for "${row.title}". Look for it in Settings, under Apps, then ChoreQuest.',
        FixOutcome.denied => 'That was refused. Tap ${row.fixLabel} again and choose Allow.',
        FixOutcome.granted || FixOutcome.opened => null,
      };
    });
    await _refresh();
  }

  /// A grown-up says a strap is ready; nothing on the phone can tell.
  Future<void> _confirmStrap() async {
    final ready = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Is a phone strap ready?'),
        content: const Text(
          'A head or chest strap made for phones, so the camera sees your child\'s hands. $neckCordWarning',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Yes, a strap is ready')),
        ],
      ),
    );
    if (ready != true || !mounted) return;
    await ref.read(strapStoreProvider).setReady(true);
    await _refresh();
  }

  Future<void> _openMaker() async {
    setState(() {
      _openingMaker = true;
      _note = null;
    });
    final outcome = await ref.read(readinessProbeProvider).openMakerBattery();
    if (!mounted) return;
    setState(() {
      _openingMaker = false;
      if (outcome == FixOutcome.unavailable) {
        _note = "This phone's battery manager did not open. Look in Settings for Battery, or for Autostart.";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Ready for alarms')),
      // Five rows: all built at once, so a screen reader reaches every one.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('For a grown-up', style: text.labelLarge?.copyWith(color: scheme.primary)),
            const SizedBox(height: 4),
            Text(
              'Quest alarms need these on this phone. Tap the button under a red row, change the setting, and come back here.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 16),
            if (result == null)
              _checked
                  ? Text("This phone can't be checked here.", style: text.bodyLarge)
                  : const Center(
                      child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
                    )
            else ...[
              _Summary(result: result),
              const SizedBox(height: 12),
              for (final row in ReadinessRow.values) ...[
                _RowCard(
                  row: row,
                  on: result.isOn(row),
                  fixing: _fixing == row,
                  onFix: _fixing == null ? () => _fix(row) : null,
                  // The strap step shows each kind, and the neck-cord warning.
                  extra: row == ReadinessRow.strap
                      ? const Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 12),
                            StrapPictures(size: 84),
                            SizedBox(height: 8),
                            Text(neckCordWarning),
                          ],
                        )
                      : null,
                ),
                const SizedBox(height: 8),
              ],
              if (result.makerBattery) _MakerCard(opening: _openingMaker, onOpen: _openingMaker ? null : _openMaker),
            ],
            const SizedBox(height: 12),
            // M11: not in a release build.
            if (kDebugMode)
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ModelBenchmarkScreen())),
                child: const Text('Model benchmark (test build)'),
              ),
            if (_note != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(_note!, style: text.bodyLarge?.copyWith(color: scheme.error)),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.result});

  final ReadinessResult result;

  @override
  Widget build(BuildContext context) {
    final colors = QuestColors.of(context);
    final tint = result.ready ? colors.approved : colors.review;
    final count = result.off.length;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: tint.fill, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Icon(result.ready ? Icons.alarm_on_rounded : Icons.alarm_off_rounded, color: tint.ink, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.ready
                    ? 'This phone is ready for quest alarms.'
                    : 'Not ready yet: ${count == 1 ? 'one thing' : '$count things'} to fix.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: tint.ink, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.row, required this.on, required this.fixing, required this.onFix, this.extra});

  final ReadinessRow row;
  final bool on;
  final bool fixing;
  final VoidCallback? onFix;

  /// More under the row, whatever its state.
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final colors = QuestColors.of(context);
    final ink = on ? colors.approved.ink : scheme.error;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              label: '${row.title}: ${on ? 'on' : 'off. ${row.whenOff}'}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(on ? Icons.check_circle_rounded : Icons.error_rounded, color: ink),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(row.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 34),
                    child: Text(on ? 'On' : row.whenOff, style: text.bodyMedium?.copyWith(color: on ? ink : null)),
                  ),
                ],
              ),
            ),
            ?extra,
            if (!on) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: FilledButton.tonal(
                  onPressed: onFix,
                  child: fixing
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(row.fixLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Some makers' battery managers stop a sleeping app whatever Android says,
/// and the app cannot read them, so this row has no green or red.
class _MakerCard extends StatelessWidget {
  const _MakerCard({required this.opening, required this.onOpen});

  final bool opening;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.battery_alert_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text("This phone's own battery manager", style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Text(
                'This phone can still stop ChoreQuest while it sleeps. Let ChoreQuest start on its own and run in the background there.',
                style: text.bodyMedium,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: OutlinedButton(
                onPressed: onOpen,
                child: opening
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Open battery manager'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
