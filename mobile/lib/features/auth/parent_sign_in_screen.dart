import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../shared/inline_error.dart';

/// Sign in, or create a parent account. One screen with a toggle rather than
/// two, since the only difference between them is a name field.
class ParentSignInScreen extends ConsumerStatefulWidget {
  const ParentSignInScreen({super.key});

  @override
  ConsumerState<ParentSignInScreen> createState() => _ParentSignInScreenState();
}

class _ParentSignInScreenState extends ConsumerState<ParentSignInScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _registering = false;
  bool _busy = false;
  ApiException? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final session = ref.read(sessionProvider.notifier);
    try {
      if (_registering) {
        await session.registerParent(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
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
              TextFormField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: _registering ? 'At least 8 characters' : null,
                  errorText: rejected?.errorFor('password'),
                ),
                validator: (v) {
                  final value = v ?? '';
                  if (value.isEmpty) return 'Enter your password.';
                  if (_registering && value.length < 8) {
                    return 'Use at least 8 characters.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) {
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
