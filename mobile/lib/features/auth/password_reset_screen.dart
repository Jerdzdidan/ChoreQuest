import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../shared/inline_error.dart';
import '../../shared/password_field.dart';
import 'password_reset_api.dart';

/// What "Forgot your password?" ends with: the email, to fill in on the
/// sign-in screen, and the server's words to show there.
typedef PasswordResetDone = ({String email, String message});

enum _Step { email, code, password }

/// "Forgot your password?" (PA-7): the email, then the 6-digit code sent to
/// it, then a new password, and back to sign in. The back button goes back
/// a step.
class PasswordResetScreen extends ConsumerStatefulWidget {
  const PasswordResetScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  ConsumerState<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends ConsumerState<PasswordResetScreen> {
  /// How long before "Send a new code" works, as the server allows.
  static const resendWait = Duration(seconds: 60);

  late final _email = TextEditingController(text: widget.initialEmail ?? '');
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _emailForm = GlobalKey<FormState>();
  final _passwordForm = GlobalKey<FormState>();

  var _step = _Step.email;
  bool _busy = false;
  String? _error;
  String? _codeError;
  String? _passwordError;

  /// Seconds until "Send a new code" works.
  int _wait = 0;
  Timer? _timer;

  PasswordResetApi get _api => PasswordResetApi(ref.read(apiClientProvider));

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  void _startWait() {
    _timer?.cancel();
    setState(() => _wait = resendWait.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait == 0) timer.cancel();
    });
  }

  /// Runs a call with the spinner on, and shows a failure that belongs to
  /// no single field in the banner.
  Future<void> _run(Future<void> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
      _codeError = null;
      _passwordError = null;
    });
    try {
      await call();
    } on ApiRejected catch (e) {
      if (!mounted) return;
      setState(() {
        _codeError = e.errorFor('code');
        _passwordError = e.errorFor('password');
        if (_codeError == null && _passwordError == null) _error = e.errorFor('email') ?? e.message;
        // The code ran out or was used up while a password was chosen.
        if (_codeError != null && _step == _Step.password) _step = _Step.code;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    if (!(_emailForm.currentState?.validate() ?? false)) return;
    await _run(() async {
      await _api.sendCode(_email.text.trim());
      if (!mounted) return;
      _code.clear();
      setState(() => _step = _Step.code);
      _startWait();
    });
  }

  Future<void> _sendAgain() => _run(() async {
        await _api.sendCode(_email.text.trim());
        if (!mounted) return;
        _startWait();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We sent a new code.')));
      });

  Future<void> _checkCode() async {
    if (_code.text.length != 6) {
      setState(() => _codeError = 'Type all 6 numbers from the email.');
      return;
    }
    await _run(() async {
      await _api.checkCode(_email.text.trim(), _code.text);
      if (mounted) setState(() => _step = _Step.password);
    });
  }

  Future<void> _reset() async {
    if (!(_passwordForm.currentState?.validate() ?? false)) return;
    await _run(() async {
      final message = await _api.reset(_email.text.trim(), _code.text, _password.text);
      if (mounted) Navigator.of(context).pop<PasswordResetDone>((email: _email.text.trim(), message: message));
    });
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;

    return PopScope(
      canPop: _step == _Step.email || _busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        setState(() {
          _step = _step == _Step.password ? _Step.code : _Step.email;
          _error = null;
        });
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Forgot your password?')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (error != null) ...[InlineError(error), const SizedBox(height: 16)],
              ...switch (_step) {
                _Step.email => _emailStep(),
                _Step.code => _codeStep(),
                _Step.password => _passwordStep(),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _busyOr(String label) => _busy
      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
      : Text(label);

  List<Widget> _emailStep() => [
        const Text('Type the email you use for ChoreQuest. We will send a 6-digit code to it.'),
        const SizedBox(height: 16),
        Form(
          key: _emailForm,
          child: TextFormField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) => (v == null || !v.contains('@')) ? 'Enter your email address.' : null,
            onFieldSubmitted: (_) => _busy ? null : _sendCode(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _busy ? null : _sendCode, child: _busyOr('Send the code')),
      ];

  List<Widget> _codeStep() {
    final text = Theme.of(context).textTheme;
    return [
      Text(
        'Enter the 6-digit code we sent to ${maskEmail(_email.text.trim())}',
        style: text.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        'It works for 15 minutes. No email? Look in spam, or send a new code.',
        style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _code,
        enabled: !_busy,
        autofocus: true,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        textAlign: TextAlign.center,
        style: text.headlineMedium?.copyWith(letterSpacing: 8, fontWeight: FontWeight.w700),
        decoration: InputDecoration(labelText: 'Code', errorText: _codeError, errorMaxLines: 3),
        onSubmitted: (_) => _busy ? null : _checkCode(),
      ),
      const SizedBox(height: 24),
      FilledButton(onPressed: _busy ? null : _checkCode, child: _busyOr('Check the code')),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy || _wait > 0 ? null : _sendAgain,
        child: Text(_wait > 0 ? 'Send a new code in $_wait s' : 'Send a new code'),
      ),
    ];
  }

  List<Widget> _passwordStep() => [
        const Text('Choose a new password. Every phone signed in to your account will need it.'),
        const SizedBox(height: 16),
        Form(
          key: _passwordForm,
          child: PasswordField(
            controller: _password,
            enabled: !_busy,
            autofocus: true,
            newPassword: true,
            labelText: 'New password',
            helperText: 'At least 8 characters',
            errorText: _passwordError,
            validator: (v) => (v == null || v.length < 8) ? 'Use at least 8 characters.' : null,
            onSubmitted: (_) => _busy ? null : _reset(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _busy ? null : _reset, child: _busyOr('Change password')),
      ];
}
