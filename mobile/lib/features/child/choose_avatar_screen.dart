import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/avatars.dart';
import '../../shared/inline_error.dart';
import '../../shared/leveling.dart';
import 'child_providers.dart';

/// A child picks their own animal from the ones their level has unlocked.
///
/// The animal is also their face on the "Who are you?" sign-in screen, so one
/// a brother or sister already has is shown as theirs and cannot be picked.
class ChooseAvatarScreen extends ConsumerStatefulWidget {
  const ChooseAvatarScreen({super.key});

  @override
  ConsumerState<ChooseAvatarScreen> createState() => _ChooseAvatarScreenState();
}

class _ChooseAvatarScreenState extends ConsumerState<ChooseAvatarScreen> {
  String? _saving;
  String? _error;

  Future<void> _pick(ChildSession me, String key, int level) async {
    if (key == me.avatar || _saving != null) return;

    // Leaving an animal kept from before it needed a level: say what it will
    // take to get it back, before it is gone.
    final leaving = avatarFor(me.avatar);
    if (!canPickAvatar(me.avatar, level: level)) {
      final change = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Change to the $key?'),
          content: Text(
            'To pick the ${me.avatar} again, you will need to reach '
            'level ${leaving.unlockLevel}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Keep the ${me.avatar}'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Change'),
            ),
          ],
        ),
      );
      if (change != true || !mounted) return;
    }

    setState(() {
      _saving = key;
      _error = null;
    });
    try {
      final child = await ref.read(childApiProvider).changeAvatar(key);
      await ref.read(sessionProvider.notifier).adoptChildProfile(child);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text("You're the $key now!")),
      );
    } on ApiRejected catch (e) {
      if (mounted) setState(() => _error = e.errorFor('avatar') ?? e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = switch (ref.watch(sessionProvider)) {
      AsyncData(value: final ChildSession s) => s,
      _ => null,
    };
    if (me == null) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final progress = ref.watch(progressProvider);
    // Until XP has loaded, only the animals open from the start are offered.
    final level = progress.hasValue ? levelFor(progress.requireValue.xp).level : 1;
    final roster = ref.watch(householdRosterProvider(me.householdCode));
    // If the household cannot be loaded, nothing is marked as taken here; the
    // server still refuses a brother's or sister's animal.
    final siblings = <String, String>{
      if (roster.hasValue)
        for (final child in roster.requireValue.children)
          if (child.id != me.id) child.avatar: child.name,
    };
    final error = _error;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose your animal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'You are level $level.',
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Do quests to reach new levels and unlock more animals.',
            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            InlineError(error),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (final key in avatars.keys)
                _AnimalTile(
                  avatarKey: key,
                  state: switch (key) {
                    _ when key == me.avatar => const _Yours(),
                    _ when siblings.containsKey(key) => _Taken(siblings[key]!),
                    _ when !canPickAvatar(key, level: level) =>
                      _Locked(avatarFor(key).unlockLevel),
                    _ => const _Open(),
                  },
                  saving: _saving == key,
                  onTap: () => _pick(me, key, level),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

sealed class _TileState {
  const _TileState();
}

final class _Yours extends _TileState {
  const _Yours();
}

final class _Open extends _TileState {
  const _Open();
}

final class _Locked extends _TileState {
  const _Locked(this.level);

  final int level;
}

final class _Taken extends _TileState {
  const _Taken(this.byName);

  final String byName;
}

class _AnimalTile extends StatelessWidget {
  const _AnimalTile({
    required this.avatarKey,
    required this.state,
    required this.saving,
    required this.onTap,
  });

  final String avatarKey;
  final _TileState state;
  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final name = avatarName(avatarKey);

    final (caption, semantics, available) = switch (state) {
      _Yours() => ('You', '$name. This is you.', false),
      _Open() => (name, name, true),
      _Locked(:final level) => ('Level $level', '$name. Unlocks at level $level.', false),
      _Taken(:final byName) => (byName, '$name. $byName has this one.', false),
    };
    final yours = state is _Yours;
    final locked = state is _Locked;

    return Semantics(
      button: available,
      selected: yours,
      enabled: available,
      label: semantics,
      child: ExcludeSemantics(
        child: SizedBox(
          width: 96,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: available ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: yours ? scheme.primary : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: Opacity(
                          opacity: available || yours ? 1 : 0.4,
                          child: AvatarBadge(avatarKey, size: 64),
                        ),
                      ),
                      if (locked)
                        const Positioned(right: 0, bottom: 0, child: _LockBadge()),
                      if (saving)
                        const SizedBox.square(
                          dimension: 40,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: text.labelLarge?.copyWith(
                      fontWeight: yours ? FontWeight.w700 : FontWeight.w500,
                      color: available || yours ? null : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockBadge extends StatelessWidget {
  const _LockBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.lock_rounded, size: 16, color: scheme.onInverseSurface),
    );
  }
}
