import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../shared/format.dart';
import '../../shared/inline_error.dart';
import 'parent_providers.dart';

/// Setting up a quest the whole household works on together (F2): what it is
/// called, how many quests to finish between them, what each child who helps
/// gets, and the days it runs.
///
/// Nothing here hands out screen time. The minutes go out when the target is
/// reached, through a grown-up's approval of a real photo (F3).
class FamilyQuestFormScreen extends ConsumerStatefulWidget {
  const FamilyQuestFormScreen({super.key});

  @override
  ConsumerState<FamilyQuestFormScreen> createState() => _FamilyQuestFormScreenState();
}

class _FamilyQuestFormScreenState extends ConsumerState<FamilyQuestFormScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();

  int _target = 10;
  int _reward = 30;
  late DateTime _starts = DateUtils.dateOnly(DateTime.now());
  late DateTime _ends = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 6));

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDays() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _starts, end: _ends),
      firstDate: today.subtract(const Duration(days: 30)),
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'The days it runs',
    );
    if (picked != null) {
      setState(() {
        _starts = DateUtils.dateOnly(picked.start);
        _ends = DateUtils.dateOnly(picked.end);
      });
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(parentApiProvider)
          .createFamilyQuest(
            title: _title.text.trim(),
            targetCount: _target,
            rewardMinutesEach: _reward,
            startsAt: _starts,
            endsAt: _ends,
          );
      ref.invalidate(familyQuestsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiRejected catch (e) {
      if (mounted) setState(() => _error = e.errorFor('ends_at') ?? e.errorFor('title') ?? e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final error = _error;
    final days = _ends.difference(_starts).inDays + 1;

    return Scaffold(
      appBar: AppBar(title: const Text('New family quest')),
      // A scroll view, not a list: a lazy list drops the fields that scroll
      // out of range, and a form whose fields are gone validates as if they
      // were all filled in.
      body: Form(
        key: _form,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'One quest for the whole household. Every quest any of your '
                'children finishes while it runs counts towards it.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'What is it called?',
                  hintText: 'Saturday clean-up',
                ),
                validator: (value) => (value ?? '').trim().isEmpty ? 'Give the quest a name.' : null,
              ),
              const SizedBox(height: 12),
              _Counter(
                label: 'Quests to finish between them',
                value: '$_target',
                onLess: _target > 1 ? () => setState(() => _target -= 1) : null,
                onMore: _target < 200 ? () => setState(() => _target += 1) : null,
              ),
              const SizedBox(height: 12),
              _Counter(
                label: 'Screen time for each child who helps',
                value: formatMinutes(_reward),
                onLess: _reward > 0 ? () => setState(() => _reward = (_reward - 5).clamp(0, 600)) : null,
                onMore: _reward < 600 ? () => setState(() => _reward = (_reward + 5).clamp(0, 600)) : null,
              ),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.date_range_rounded),
                  title: Text('${formatDay(context, _starts)} to ${formatDay(context, _ends)}'),
                  subtitle: Text(days == 1 ? 'One day' : '$days days'),
                  trailing: TextButton(onPressed: _pickDays, child: const Text('Change')),
                ),
              ),
              if (error != null) ...[const SizedBox(height: 16), InlineError(error)],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.groups_rounded),
                label: Text(_saving ? 'Starting…' : 'Start the quest'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A figure with a minus and a plus, for a parent setting a target or a
/// reward without a keyboard.
class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value, required this.onLess, required this.onMore});

  final String label;
  final String value;
  final VoidCallback? onLess;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Row(
        children: [
          Expanded(child: Text(label, style: text.bodyLarge)),
          IconButton.filledTonal(onPressed: onLess, icon: const Icon(Icons.remove_rounded), tooltip: 'Less'),
          SizedBox(
            width: 76,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton.filledTonal(onPressed: onMore, icon: const Icon(Icons.add_rounded), tooltip: 'More'),
        ],
      ),
    );
  }
}

/// "23 Sep", in the phone's own language.
String formatDay(BuildContext context, DateTime day) =>
    MaterialLocalizations.of(context).formatShortMonthDay(day);
