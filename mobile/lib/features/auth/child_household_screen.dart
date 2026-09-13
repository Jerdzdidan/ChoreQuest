import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../shared/inline_error.dart';
import 'child_avatar_screen.dart';
import 'household_api.dart';

/// Pairs this phone with a household. Done once, by a grown-up.
class ChildHouseholdScreen extends ConsumerStatefulWidget {
  const ChildHouseholdScreen({super.key});

  @override
  ConsumerState<ChildHouseholdScreen> createState() =>
      _ChildHouseholdScreenState();
}

class _ChildHouseholdScreenState extends ConsumerState<ChildHouseholdScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'The household code has 6 letters and numbers.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final roster =
          await fetchHouseholdRoster(ref.read(apiClientProvider), code);
      await ref.read(sessionStoreProvider).writeHouseholdCode(roster.code);
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              ChildAvatarScreen(householdCode: roster.code, roster: roster),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final error = _error;

    return Scaffold(
      appBar: AppBar(title: const Text('Set up this phone')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Household code', style: text.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'A grown-up types this once. It is shown on their ChoreQuest '
              'home screen.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _code,
              enabled: !_busy,
              autofocus: true,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              style: text.headlineMedium?.copyWith(
                letterSpacing: 6,
                fontWeight: FontWeight.w600,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(6),
                _UpperCase(),
              ],
              decoration: const InputDecoration(
                hintText: '······',
                counterText: '',
              ),
              onSubmitted: (_) {
                if (!_busy) _continue();
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              InlineError(error),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _continue,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
