import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../core/session/session_store.dart';
import '../../shared/inline_error.dart';
import 'household_api.dart';
import 'parent_pin_screen.dart';
import 'parent_sign_in_screen.dart';
import 'profile_tile.dart';

/// The grown-up "Who are you?" (PA-5), on a phone that knows its household.
///
/// A grown-up whose PIN works here goes to the PIN pad. One with no PIN, or
/// who has not yet signed in on this phone with their password, goes to
/// email and password with their email filled in when the phone knows it.
class GrownUpWhoScreen extends ConsumerStatefulWidget {
  const GrownUpWhoScreen({super.key, required this.householdCode});

  final String householdCode;

  @override
  ConsumerState<GrownUpWhoScreen> createState() => _GrownUpWhoScreenState();
}

class _GrownUpWhoScreenState extends ConsumerState<GrownUpWhoScreen> {
  late Future<(HouseholdRoster, Map<int, KnownGrownUp>)> _load = _fetch();

  Future<(HouseholdRoster, Map<int, KnownGrownUp>)> _fetch() async => (
        await fetchHouseholdRoster(ref.read(apiClientProvider), widget.householdCode),
        await ref.read(sessionStoreProvider).readGrownUps(),
      );

  void _open(RosterParent parent, KnownGrownUp? known) {
    final usePin = parent.pin && known?.pinTicket != null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => usePin
            ? ParentPinScreen(parent: parent, householdCode: widget.householdCode, email: known?.email)
            : ParentSignInScreen(
                initialEmail: known?.email,
                // Their PIN is set, but this phone has not seen their password.
                notice: parent.pin ? 'Sign in here once with your password, and your PIN will work on this phone.' : null,
              ),
      ),
    );
  }

  void _password({bool registering = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ParentSignInScreen(registering: registering)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final links = Column(
      children: [
        TextButton(
          onPressed: () => _password(registering: true),
          child: const Text('New to ChoreQuest? Create an account'),
        ),
        TextButton(
          onPressed: _password,
          child: const Text('Sign in with email and password'),
        ),
        const SizedBox(height: 8),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Who are you?')),
      body: SafeArea(
        child: FutureBuilder(
          future: _load,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final error = snapshot.error;
            if (error != null || snapshot.requireData.$1.parents.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  InlineError(
                    error is ApiException ? error.message : 'This household could not be loaded.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() => _load = _fetch()),
                    child: const Text('Try again'),
                  ),
                  const SizedBox(height: 8),
                  links,
                ],
              );
            }

            final (roster, known) = snapshot.requireData;
            return Column(
              children: [
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: roster.parents.length,
                    itemBuilder: (context, i) {
                      final parent = roster.parents[i];
                      return ProfileTile(
                        avatar: parent.avatar,
                        name: parent.name,
                        onTap: () => _open(parent, known[parent.id]),
                      );
                    },
                  ),
                ),
                links,
              ],
            );
          },
        ),
      ),
    );
  }
}
