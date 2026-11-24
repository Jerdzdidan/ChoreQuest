import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../shared/avatars.dart';
import 'household_api.dart';
import 'parent_sign_in_screen.dart';
import 'pin_pad.dart';

/// A grown-up's PIN (PA-5), on a phone where they signed in with their
/// password before. A wrong PIN says how many tries are left; the fifth, or
/// a PIN that is off, sends them to email and password with the reason.
class ParentPinScreen extends ConsumerWidget {
  const ParentPinScreen({
    super.key,
    required this.parent,
    required this.householdCode,
    this.email,
  });

  final RosterParent parent;
  final String householdCode;

  /// Their email as this phone remembers it, to fill in if they need it.
  final String? email;

  void _usePassword(BuildContext context, {String? notice}) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ParentSignInScreen(initialEmail: email, notice: notice),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: PinPad(
          header: PinHeader(
            avatar: AvatarBadge(parent.avatar, size: 96),
            name: parent.name,
            hint: 'Type your sign-in PIN',
          ),
          onComplete: (pin) async {
            try {
              await ref.read(sessionProvider.notifier).signInParentWithPin(
                    householdCode: householdCode,
                    parentId: parent.id,
                    pin: pin,
                  );
              // On success the root opens the parent home and discards
              // this screen.
              return null;
            } on ApiLocked catch (e) {
              if (context.mounted) _usePassword(context, notice: e.message);
              return null;
            } on ApiException catch (e) {
              return e.message;
            }
          },
          footer: TextButton(
            onPressed: () => _usePassword(context),
            child: const Text('Sign in with email and password'),
          ),
        ),
      ),
    );
  }
}
