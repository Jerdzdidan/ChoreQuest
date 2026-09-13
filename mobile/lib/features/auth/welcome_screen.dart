import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session_controller.dart';
import 'child_avatar_screen.dart';
import 'child_household_screen.dart';
import 'parent_sign_in_screen.dart';

/// The first thing anyone sees: two doors, sized for the smallest hand that
/// will use them, and told apart by picture before words.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  Future<void> _openChild(BuildContext context, WidgetRef ref) async {
    // A phone paired with a household goes straight to its faces.
    final code = await ref.read(sessionStoreProvider).readHouseholdCode();
    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => code == null
            ? const ChildHouseholdScreen()
            : ChildAvatarScreen(householdCode: code),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        // Spaced out when there is room, scrollable when there is not: a small
        // phone with its text size turned up must still reach both doors.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      Text(
                        'ChoreQuest',
                        textAlign: TextAlign.center,
                        style: text.displaySmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Chores first, then screen time.',
                        textAlign: TextAlign.center,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: 32),
                      const Spacer(),
                      // Emoji from Unicode 6, which every Android version
                      // draws. The single-person child and adult emoji came
                      // later and show as empty boxes on the Android 7 and 8
                      // phones this study includes.
                      _Door(
                        emoji: '👧👦',
                        label: "I'm a kid",
                        highlighted: true,
                        onTap: () => _openChild(context, ref),
                      ),
                      const SizedBox(height: 16),
                      _Door(
                        emoji: '👩👨',
                        label: "I'm a grown-up",
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ParentSignInScreen(),
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Door extends StatelessWidget {
  const _Door({
    required this.emoji,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        highlighted ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final foreground =
        highlighted ? scheme.onPrimaryContainer : scheme.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Text(emoji, style: const TextStyle(fontSize: 34)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
