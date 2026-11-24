import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../shared/inline_error.dart';
import '../../shared/password_field.dart';
import '../auth/set_pin_screen.dart';
import 'parent_providers.dart';

/// Set up or change the sign-in PIN from the Profile (PA-6): the password
/// first, so a phone left unlocked cannot be given a PIN someone else
/// knows, then the PIN twice. Pops with true once it is saved.
class SignInPinScreen extends ConsumerStatefulWidget {
  const SignInPinScreen({super.key, required this.changing});

  /// "Change PIN" rather than "Set up a PIN".
  final bool changing;

  @override
  ConsumerState<SignInPinScreen> createState() => _SignInPinScreenState();
}

class _SignInPinScreenState extends ConsumerState<SignInPinScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  String? _passwordError;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final choice = await Navigator.of(context).push<PinChoice>(
      MaterialPageRoute(builder: (_) => const SetPinScreen()),
    );
    final pin = choice?.pin;
    if (pin == null || !mounted) return;

    setState(() {
      _busy = true;
      _passwordError = null;
      _error = null;
    });
    try {
      final saved = await ref.read(parentApiProvider).setPin(pin: pin, currentPassword: _password.text);
      final session = ref.read(sessionProvider.notifier);
      await session.adoptParentProfile(saved.parent);
      await session.rememberPinTicket(saved.pinTicket);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiRejected catch (e) {
      if (mounted) {
        setState(() {
          _passwordError = e.errorFor('current_password');
          if (_passwordError == null) _error = e.errorFor('pin') ?? e.message;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: Text(widget.changing ? 'Change PIN' : 'Set up a PIN')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('First, your password. Then choose 4 numbers to sign in with on this phone.'),
              const SizedBox(height: 16),
              if (error != null) ...[InlineError(error), const SizedBox(height: 16)],
              PasswordField(
                controller: _password,
                enabled: !_busy,
                autofocus: true,
                labelText: 'Your password',
                errorText: _passwordError,
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password.' : null,
                onSubmitted: (_) => _busy ? null : _continue(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _continue,
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
