import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../shared/avatars.dart';
import 'household_api.dart';
import 'pin_pad.dart';

/// A child's four digits. A wrong PIN clears the dots and says so; the words
/// come from the server, which already phrases them for a child.
class ChildPinScreen extends ConsumerWidget {
  const ChildPinScreen({
    super.key,
    required this.profile,
    required this.householdCode,
  });

  final RosterChild profile;
  final String householdCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: PinPad(
          header: PinHeader(avatar: AvatarBadge(profile.avatar, size: 96), name: profile.name),
          onComplete: (pin) async {
            try {
              await ref.read(sessionProvider.notifier).signInChild(
                    householdCode: householdCode,
                    childId: profile.id,
                    pin: pin,
                  );
              // On success the root opens this child's home and discards
              // this screen.
              return null;
            } on ApiException catch (e) {
              return e.message;
            }
          },
        ),
      ),
    );
  }
}
