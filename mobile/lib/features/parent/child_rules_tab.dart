import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/allocation_rule.dart';
import '../../core/models/child_profile.dart';
import '../../shared/async_view.dart';
import '../../shared/format.dart';
import '../../shared/inline_error.dart';
import 'parent_providers.dart';

/// A child's screen-time rules, edited as a draft and saved together.
class ChildRulesTab extends ConsumerStatefulWidget {
  const ChildRulesTab({super.key, required this.child});

  final ChildProfile child;

  @override
  ConsumerState<ChildRulesTab> createState() => _ChildRulesTabState();
}

class _ChildRulesTabState extends ConsumerState<ChildRulesTab>
    with AutomaticKeepAliveClientMixin {
  /// Unsaved edits. Null means the form shows what the server has.
  AllocationRule? _draft;
  bool _busy = false;
  String? _error;

  /// Keeps unsaved edits when the parent flips to the Chores tab and back.
  @override
  bool get wantKeepAlive => true;

  void _edit(AllocationRule next) {
    setState(() {
      _draft = next;
      _error = null;
    });
  }

  Future<void> _save(AllocationRule draft) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await ref.read(parentApiProvider).updateRule(draft);
      ref.invalidate(ruleProvider(widget.child.id));
      if (!mounted) return;
      // Hold the saved values until the refetch lands, so the form never
      // flickers back to the old ones.
      setState(() => _draft = saved);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Rules saved')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rule = ref.watch(ruleProvider(widget.child.id));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AsyncView<AllocationRule>(
          value: rule,
          onRetry: () => ref.invalidate(ruleProvider(widget.child.id)),
          builder: _form,
        ),
      ],
    );
  }

  Widget _form(BuildContext context, AllocationRule fetched) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final draft = _draft ?? fetched;
    final dirty = _draft != null && _draft != fetched;
    final problem = draft.problem;
    final error = _error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Earning screen time', style: text.titleMedium),
        const SizedBox(height: 8),
        _StepperRow(
          label: 'Minutes for each point',
          value: draft.minutesPerPoint,
          min: 1,
          max: 120,
          display: formatMinutes(draft.minutesPerPoint),
          onChanged: _busy
              ? null
              : (v) => _edit(draft.copyWith(minutesPerPoint: v)),
        ),
        Text(
          'A 5-point chore earns ${formatMinutes(5 * draft.minutesPerPoint)}.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _MinutesSlider(
          label: 'Most earned per day',
          value: draft.dailyCapMinutes,
          max: math.max(240, draft.dailyCapMinutes),
          step: 5,
          onChanged: _busy
              ? null
              : (v) => _edit(draft.copyWith(dailyCapMinutes: v)),
        ),
        _MinutesSlider(
          label: 'Most earned per week',
          value: draft.weeklyCapMinutes,
          max: math.max(1680, draft.weeklyCapMinutes),
          step: 30,
          onChanged: _busy
              ? null
              : (v) => _edit(draft.copyWith(weeklyCapMinutes: v)),
        ),
        const SizedBox(height: 24),
        Text('Automatic photo checking', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Only "Make the bed", "Clear the table" and "Sweep the floor" are '
          'checked automatically. Every other chore always comes to you.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        RangeSlider(
          values: RangeValues(draft.confidenceLow, draft.confidenceHigh),
          min: 0,
          max: 1,
          divisions: 20,
          labels: RangeLabels(
            formatPercent(draft.confidenceLow),
            formatPercent(draft.confidenceHigh),
          ),
          onChanged: _busy
              ? null
              : (values) => _edit(
                    draft.copyWith(
                      confidenceLow: _hundredths(values.start),
                      confidenceHigh: _hundredths(values.end),
                    ),
                  ),
        ),
        _ThresholdLegend(low: draft.confidenceLow, high: draft.confidenceHigh),
        if (problem != null) ...[
          const SizedBox(height: 12),
          InlineError(problem),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          InlineError(error),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: dirty && !_busy
                    ? () => setState(() {
                          _draft = null;
                          _error = null;
                        })
                    : null,
                child: const Text('Undo changes'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed:
                    dirty && problem == null && !_busy ? () => _save(draft) : null,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save rules'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static double _hundredths(double value) => (value * 100).round() / 100;
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String display;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;

    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton.filledTonal(
          tooltip: 'Less',
          onPressed: change == null || value <= min ? null : () => change(value - 1),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 72,
          child: Text(
            display,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'More',
          onPressed: change == null || value >= max ? null : () => change(value + 1),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _MinutesSlider extends StatelessWidget {
  const _MinutesSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final int step;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              formatMinutes(value),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: max.toDouble(),
          divisions: math.max(1, max ~/ step),
          label: formatMinutes(value),
          onChanged: change == null
              ? null
              : (raw) => change((raw / step).round() * step),
        ),
      ],
    );
  }
}

class _ThresholdLegend extends StatelessWidget {
  const _ThresholdLegend({required this.low, required this.high});

  final double low;
  final double high;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LegendRow(
          colour: const Color(0xFF2E7D32),
          text: 'At least ${formatPercent(high)} sure it is done: approved '
              'automatically, and the screen time is added.',
        ),
        _LegendRow(
          colour: const Color(0xFFB7791F),
          text: 'Between ${formatPercent(low)} and ${formatPercent(high)}: '
              'sent to you to decide.',
        ),
        _LegendRow(
          colour: const Color(0xFFC0392B),
          text: '${formatPercent(low)} or less: your child is asked for another '
              'photo. You can still approve it yourself.',
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.colour, required this.text});

  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
