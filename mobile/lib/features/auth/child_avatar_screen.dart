import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../shared/avatars.dart';
import '../../shared/inline_error.dart';
import 'child_household_screen.dart';
import 'child_pin_screen.dart';
import 'household_api.dart';

/// "Who are you?" Every child in the household, as a face to tap.
class ChildAvatarScreen extends ConsumerStatefulWidget {
  const ChildAvatarScreen({
    super.key,
    required this.householdCode,
    this.roster,
  });

  final String householdCode;

  /// Passed through when the roster was fetched moments ago while pairing, so
  /// it is not fetched twice in a row.
  final HouseholdRoster? roster;

  @override
  ConsumerState<ChildAvatarScreen> createState() => _ChildAvatarScreenState();
}

class _ChildAvatarScreenState extends ConsumerState<ChildAvatarScreen> {
  late Future<HouseholdRoster> _roster;

  @override
  void initState() {
    super.initState();
    final preloaded = widget.roster;
    _roster = preloaded != null ? Future.value(preloaded) : _load();
  }

  Future<HouseholdRoster> _load() =>
      fetchHouseholdRoster(ref.read(apiClientProvider), widget.householdCode);

  void _retry() => setState(() => _roster = _load());

  Future<void> _useDifferentCode() async {
    await ref.read(sessionStoreProvider).forgetHousehold();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ChildHouseholdScreen()),
    );
  }

  void _openPin(RosterChild profile, String householdCode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChildPinScreen(profile: profile, householdCode: householdCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Who are you?')),
      body: SafeArea(
        child: FutureBuilder<HouseholdRoster>(
          future: _roster,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final error = snapshot.error;
            if (error != null) {
              return _Problem(
                message: error is ApiException
                    ? error.message
                    : 'This household could not be loaded.',
                // A code the server no longer recognises cannot be retried
                // into working; only a different code will help.
                onRetry: error is ApiRejected && error.statusCode == 404
                    ? null
                    : _retry,
                onChangeCode: _useDifferentCode,
              );
            }

            final roster = snapshot.requireData;
            if (roster.children.isEmpty) {
              return _Problem(
                message: 'No children are set up in this household yet. A '
                    'grown-up can add them from their ChoreQuest home.',
                onRetry: _retry,
                onChangeCode: _useDifferentCode,
              );
            }

            return Column(
              children: [
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: roster.children.length,
                    itemBuilder: (context, i) {
                      final profile = roster.children[i];
                      return _ProfileTile(
                        profile: profile,
                        onTap: () => _openPin(profile, roster.code),
                      );
                    },
                  ),
                ),
                TextButton(
                  onPressed: _useDifferentCode,
                  child: const Text('Use a different household code'),
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profile, required this.onTap});

  final RosterChild profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AvatarBadge(profile.avatar, size: 96),
            const SizedBox(height: 12),
            Text(
              profile.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.message,
    required this.onChangeCode,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback onChangeCode;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        InlineError(message),
        const SizedBox(height: 16),
        if (retry != null)
          FilledButton(onPressed: retry, child: const Text('Try again')),
        TextButton(
          onPressed: onChangeCode,
          child: const Text('Use a different household code'),
        ),
      ],
    );
  }
}
