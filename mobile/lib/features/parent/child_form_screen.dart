import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/api_dates.dart';
import '../../core/models/child_profile.dart';
import '../../shared/avatars.dart';
import '../../shared/inline_error.dart';
import 'parent_providers.dart';

/// Add a child, or edit one. Editing can also set a new PIN, which is how a
/// parent unlocks a profile locked by too many wrong tries.
class ChildFormScreen extends ConsumerStatefulWidget {
  const ChildFormScreen({super.key, this.existing});

  final ChildProfile? existing;

  @override
  ConsumerState<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends ConsumerState<ChildFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  final _pin = TextEditingController();
  final _pinAgain = TextEditingController();

  late String _avatar = widget.existing?.avatar ?? avatars.keys.first;
  late DateTime? _birthdate = widget.existing?.birthdate;
  late bool _setPin = widget.existing == null;

  bool _busy = false;
  ApiException? _error;
  String? _birthdateError;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _pinAgain.dispose();
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final first = DateTime(today.year - 16);
    final last = today.subtract(const Duration(days: 1));
    var initial = _birthdate ?? DateTime(today.year - 6, today.month, today.day);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Birthday',
    );
    if (picked != null) {
      setState(() {
        _birthdate = picked;
        _birthdateError = null;
      });
    }
  }

  Future<void> _save() async {
    final fieldsValid = _form.currentState?.validate() ?? false;
    final birthdate = _birthdate;
    if (birthdate == null) {
      setState(() => _birthdateError = 'Choose a birthday.');
    }
    if (!fieldsValid || birthdate == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final api = ref.read(parentApiProvider);
    final name = _name.text.trim();
    try {
      final existing = widget.existing;
      if (existing == null) {
        await api.addChild(
          name: name,
          avatar: _avatar,
          birthdate: birthdate,
          pin: _pin.text,
        );
      } else {
        await api.updateChild(
          existing.id,
          name: name != existing.name ? name : null,
          avatar: _avatar != existing.avatar ? _avatar : null,
          birthdate: isoDate(birthdate) != isoDate(existing.birthdate)
              ? birthdate
              : null,
          pin: _setPin ? _pin.text : null,
        );
      }
      ref.invalidate(childrenProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final existing = widget.existing;
    final rejected = switch (_error) {
      final ApiRejected r => r,
      _ => null,
    };
    final error = _error;
    final showBanner =
        error != null && (rejected == null || rejected.fieldErrors.isEmpty);

    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? 'Add a child' : 'Edit ${existing.name}'),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (showBanner) ...[
                InlineError(error.message),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _name,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: "Child's first name",
                  errorText: rejected?.errorFor('name'),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name.' : null,
              ),
              const SizedBox(height: 16),
              _BirthdayField(
                date: _birthdate,
                error: _birthdateError ?? rejected?.errorFor('birthdate'),
                onTap: _busy ? null : _pickBirthdate,
              ),
              const SizedBox(height: 24),
              Text('Picture', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Your child taps this to sign in, so let them choose it.',
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              _AvatarChooser(
                selected: _avatar,
                onSelected:
                    _busy ? null : (key) => setState(() => _avatar = key),
              ),
              const SizedBox(height: 24),
              if (existing != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _setPin,
                  onChanged: _busy ? null : (v) => setState(() => _setPin = v),
                  title: const Text('Set a new PIN'),
                  subtitle: Text(
                    existing.isLocked
                        ? 'Locked out after too many wrong tries. A new PIN '
                            'unlocks it.'
                        : 'Leave this off to keep the current PIN.',
                  ),
                ),
              if (_setPin) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _pin,
                  enabled: !_busy,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    labelText: 'PIN (4 numbers)',
                    errorText: rejected?.errorFor('pin'),
                  ),
                  validator: (v) => RegExp(r'^\d{4}$').hasMatch(v ?? '')
                      ? null
                      : 'Use exactly 4 numbers.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pinAgain,
                  enabled: !_busy,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration:
                      const InputDecoration(labelText: 'Type the PIN again'),
                  validator: (v) =>
                      v == _pin.text ? null : "The two PINs don't match.",
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(existing == null ? 'Add child' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BirthdayField extends StatelessWidget {
  const _BirthdayField({
    required this.date,
    required this.error,
    required this.onTap,
  });

  final DateTime? date;
  final String? error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final picked = date;
    final age = picked == null ? null : ageOn(picked, DateTime.now());
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            isEmpty: picked == null,
            decoration: InputDecoration(
              labelText: 'Birthday',
              errorText: error,
              suffixIcon: const Icon(Icons.calendar_today),
            ),
            child: picked == null
                ? null
                : Text(
                    '${MaterialLocalizations.of(context).formatMediumDate(picked)}'
                    ' · age $age',
                  ),
          ),
        ),
        if (age != null && (age < 4 || age > 10))
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              "ChoreQuest's chores are made for ages 4 to 10, so the "
              'catalogue may be empty for this age.',
              style: TextStyle(color: scheme.tertiary),
            ),
          ),
      ],
    );
  }
}

class _AvatarChooser extends StatelessWidget {
  const _AvatarChooser({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final select = onSelected;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final key in avatars.keys)
          Semantics(
            button: true,
            selected: key == selected,
            label: key,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: select == null ? null : () => select(key),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: key == selected ? scheme.primary : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: AvatarBadge(key, size: 52),
              ),
            ),
          ),
      ],
    );
  }
}
