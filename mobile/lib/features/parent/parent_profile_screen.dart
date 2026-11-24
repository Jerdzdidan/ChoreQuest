import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/avatars.dart';
import '../../shared/credits_screen.dart';
import '../../shared/inline_error.dart';
import '../../shared/password_field.dart';
import 'child_form_screen.dart';
import 'parent_providers.dart';
import 'sign_in_pin_screen.dart';

/// The parent's own account: their picture, name, email and password.
///
/// Only what they change is sent. A new password needs the current one, so a
/// phone left unlocked cannot be used to take the account over.
class ParentProfileScreen extends ConsumerStatefulWidget {
  const ParentProfileScreen({super.key});

  @override
  ConsumerState<ParentProfileScreen> createState() =>
      _ParentProfileScreenState();
}

class _ParentProfileScreenState extends ConsumerState<ParentProfileScreen> {
  final _details = GlobalKey<FormState>();
  final _passwords = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();

  String? _avatar;
  bool _loaded = false;
  bool _savingDetails = false;
  bool _savingPassword = false;
  bool _savingPin = false;
  String? _detailsError;
  String? _passwordError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  /// Fills the fields once, from the signed-in account, and then leaves what
  /// the parent is typing alone.
  void _fillOnce(ParentSession parent) {
    if (_loaded) return;
    _loaded = true;
    _name.text = parent.name;
    _email.text = parent.email;
    _avatar = parent.avatar;
  }

  Future<void> _saveDetails() async {
    if (!(_details.currentState?.validate() ?? false)) return;
    setState(() {
      _savingDetails = true;
      _detailsError = null;
    });
    try {
      final saved = await ref.read(parentApiProvider).updateAccount(
            name: _name.text.trim(),
            email: _email.text.trim(),
            avatar: _avatar,
          );
      await ref.read(sessionProvider.notifier).adoptParentProfile(saved.parent);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Account saved.')));
    } on ApiRejected catch (e) {
      if (mounted) {
        setState(() => _detailsError =
            e.errorFor('email') ?? e.errorFor('name') ?? e.message);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _detailsError = e.message);
    } finally {
      if (mounted) setState(() => _savingDetails = false);
    }
  }

  Future<void> _savePassword() async {
    if (!(_passwords.currentState?.validate() ?? false)) return;
    setState(() {
      _savingPassword = true;
      _passwordError = null;
    });
    try {
      final saved = await ref.read(parentApiProvider).updateAccount(
            password: _newPassword.text,
            currentPassword: _currentPassword.text,
          );
      // A new password retires every phone's pin ticket; this one gets a
      // fresh one, so the PIN keeps working here.
      final ticket = saved.pinTicket;
      if (ticket != null) await ref.read(sessionProvider.notifier).rememberPinTicket(ticket);
      if (!mounted) return;
      _currentPassword.clear();
      _newPassword.clear();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password changed.')));
    } on ApiRejected catch (e) {
      if (mounted) {
        setState(() => _passwordError =
            e.errorFor('current_password') ?? e.errorFor('password') ?? e.message);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _passwordError = e.message);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  /// "Set up a PIN" or "Change PIN" (PA-6).
  Future<void> _setPin({required bool changing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SignInPinScreen(changing: changing)),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(changing ? 'Your PIN is changed.' : 'Your PIN is set.')),
      );
    }
  }

  /// "Turn off PIN": a PIN only takes the password's place, so turning it
  /// off asks nothing more than a yes.
  Future<void> _turnOffPin() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off your PIN?'),
        content: const Text('You will sign in with your email and password.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Turn off PIN')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _savingPin = true);
    try {
      final saved = await ref.read(parentApiProvider).removePin();
      await ref.read(sessionProvider.notifier).adoptParentProfile(saved);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your PIN is off.')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _savingPin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = switch (ref.watch(sessionProvider)) {
      AsyncData(value: final ParentSession p) => p,
      _ => null,
    };
    if (parent == null) return const SizedBox.shrink();
    _fillOnce(parent);

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final detailsError = _detailsError;
    final passwordError = _passwordError;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Your account', style: text.titleMedium),
        const SizedBox(height: 8),
        Form(
          key: _details,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Your picture',
                style: text.titleSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final key in avatars.keys)
                    Semantics(
                      button: true,
                      selected: key == _avatar,
                      label: avatarName(key),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _savingDetails
                            ? null
                            : () => setState(() => _avatar = key),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: key == _avatar
                                  ? scheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: AvatarBadge(key, size: 44),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                enabled: !_savingDetails,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Your name'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter your name.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                enabled: !_savingDetails,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Enter your email address.'
                    : null,
              ),
              if (detailsError != null) ...[
                const SizedBox(height: 12),
                InlineError(detailsError),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _savingDetails ? null : _saveDetails,
                child: _savingDetails
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save account'),
              ),
            ],
          ),
        ),
        const Divider(height: 40),
        Text('Change password', style: text.titleMedium),
        const SizedBox(height: 8),
        Form(
          key: _passwords,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PasswordField(
                controller: _currentPassword,
                enabled: !_savingPassword,
                labelText: 'Current password',
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Enter your current password.'
                    : null,
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _newPassword,
                enabled: !_savingPassword,
                labelText: 'New password',
                newPassword: true,
                validator: (v) => (v == null || v.length < 8)
                    ? 'Use at least 8 characters.'
                    : null,
              ),
              if (passwordError != null) ...[
                const SizedBox(height: 12),
                InlineError(passwordError),
              ],
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _savingPassword ? null : _savePassword,
                child: _savingPassword
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Change password'),
              ),
            ],
          ),
        ),
        const Divider(height: 40),
        Text('Sign-in PIN', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          parent.hasPin
              ? 'On. On a phone where you have signed in with your password, you can sign in with 4 numbers. '
                  'After 5 wrong tries you will need your password.'
              : 'Off. You sign in with your email and password.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (!parent.hasPin)
          OutlinedButton.icon(
            onPressed: _savingPin ? null : () => _setPin(changing: false),
            icon: const Icon(Icons.pin_outlined),
            label: const Text('Set up a PIN'),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: _savingPin ? null : () => _setPin(changing: true),
                icon: const Icon(Icons.pin_outlined),
                label: const Text('Change PIN'),
              ),
              TextButton(
                onPressed: _savingPin ? null : _turnOffPin,
                child: const Text('Turn off PIN'),
              ),
            ],
          ),
        const Divider(height: 40),
        Text('Your children', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Open a child to change their name, picture, birthday or PIN. '
          'A new PIN replaces the old one straight away.',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        switch (ref.watch(childrenProvider)) {
          AsyncData(value: final children) => Column(
              children: [
                for (final child in children)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: AvatarBadge(child.avatar, size: 40),
                    title: Text(child.name),
                    subtitle: Text(
                      child.isLocked
                          ? 'Locked out: a new PIN lets them back in'
                          : 'Age ${child.age}',
                      style: child.isLocked
                          ? TextStyle(color: scheme.error)
                          : null,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChildFormScreen(existing: child),
                      ),
                    ),
                  ),
              ],
            ),
          AsyncError() => Text(
              "Couldn't load your children.",
              style: text.bodyMedium?.copyWith(color: scheme.error),
            ),
          _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
        },
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChildFormScreen()),
          ),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Add a child'),
        ),
        const Divider(height: 40),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Artwork and credits'),
          subtitle: const Text('Who drew the pictures, and the videos the movement check learned from'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CreditsScreen()),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => ref.read(sessionProvider.notifier).signOut(),
        ),
      ],
    );
  }
}
