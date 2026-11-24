import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../shared/inline_error.dart';
import '../../shared/password_field.dart';
import 'password_reset_screen.dart';
import 'set_pin_screen.dart';

/// Sign in, or create a parent account. One screen with a toggle rather than
/// two, since the only difference between them is a name field. Creating an
/// account offers a 4-digit PIN, which can be skipped (PA-6).
class ParentSignInScreen extends ConsumerStatefulWidget {
  const ParentSignInScreen({
    super.key,
    this.initialEmail,
    this.registering = false,
    this.notice,
  });

  /// Filled in when the phone knows who is signing in.
  final String? initialEmail;

  /// Opens on "Create a parent account".
  final bool registering;

  /// Why they are here, such as five wrong PINs.
  final String? notice;

  @override
  ConsumerState<ParentSignInScreen> createState() => _ParentSignInScreenState();
}

class _ParentSignInScreenState extends ConsumerState<ParentSignInScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _password = TextEditingController();

  late bool _registering = widget.registering;
  bool _busy = false;
  ApiException? _error;
  late String? _notice = widget.notice;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    // The optional PIN step comes before the account is made: once it is,
    // the app opens the parent home straight away.
    PinChoice? choice;
    if (_registering) {
      choice = await Navigator.of(context).push<PinChoice>(
        MaterialPageRoute(builder: (_) => const SetPinScreen(skippable: true)),
      );
      if (choice == null || !mounted) return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    final session = ref.read(sessionProvider.notifier);
    try {
      if (_registering) {
        await session.registerParent(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          pin: choice?.pin,
        );
      } else {
        await session.signInParent(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      // Success needs no navigation here. The root swaps to the parent home
      // and discards this screen along with the rest of the signed-out stack.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _registering = !_registering;
      _error = null;
      _notice = null;
    });
  }

  Future<void> _forgot() async {
    final done = await Navigator.of(context).push<PasswordResetDone>(
      MaterialPageRoute(builder: (_) => PasswordResetScreen(initialEmail: _email.text.trim())),
    );
    if (done == null || !mounted) return;
    setState(() {
      _email.text = done.email;
      _password.clear();
      _error = null;
      _notice = done.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rejected = switch (_error) {
      final ApiRejected r => r,
      _ => null,
    };

    // Field-level problems are shown under their fields. Anything else, such
    // as the server being unreachable, gets the banner.
    final error = _error;
    final showBanner =
        error != null && (rejected == null || rejected.fieldErrors.isEmpty);

    return Scaffold(
      appBar: AppBar(
        title: Text(_registering ? 'Create a parent account' : 'Parent sign in'),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_notice case final notice?) ...[
                _Notice(notice),
                const SizedBox(height: 16),
              ],
              if (showBanner) ...[
                InlineError(error.message),
                const SizedBox(height: 16),
              ],
              if (_registering) ...[
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: InputDecoration(
                    labelText: 'Your name',
                    errorText: rejected?.errorFor('name'),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter your name.' : null,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _email,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: 'Email',
                  errorText: rejected?.errorFor('email'),
                ),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Enter your email address.'
                    : null,
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                enabled: !_busy,
                newPassword: _registering,
                helperText: _registering ? 'At least 8 characters' : null,
                errorText: rejected?.errorFor('password'),
                validator: (v) {
                  final value = v ?? '';
                  if (value.isEmpty) return 'Enter your password.';
                  if (_registering && value.length < 8) {
                    return 'Use at least 8 characters.';
                  }
                  return null;
                },
                onSubmitted: (_) {
                  if (!_busy) _submit();
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_registering ? 'Create account' : 'Sign in'),
              ),
              if (!_registering)
                TextButton(
                  onPressed: _busy ? null : _forgot,
                  child: const Text('Forgot your password?'),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _toggleMode,
                child: Text(
                  _registering
                      ? 'I already have an account'
                      : 'New to ChoreQuest? Create an account',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A calm line above the form: why the grown-up is here, or that their
/// password was changed.
class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: TextStyle(color: scheme.onSecondaryContainer)),
            ),
          ],
        ),
      ),
    );
  }
}
