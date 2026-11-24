import 'package:flutter/material.dart';

import 'pin_pad.dart';

/// What the "Set a 4-digit PIN" step ended with: the PIN, or null when it
/// was skipped. Going back returns no result at all.
typedef PinChoice = ({String? pin});

/// Choose a 4-digit sign-in PIN, then type it again (PA-6). Used when an
/// account is made, where it can be skipped, and from the Profile.
class SetPinScreen extends StatefulWidget {
  const SetPinScreen({super.key, this.skippable = false});

  /// Creating an account: the PIN is optional.
  final bool skippable;

  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  /// The first entry, waiting to be typed again.
  String? _first;

  /// Shown above the pad after the two entries were different.
  String? _mismatch;

  Future<String?> _entered(String pin) async {
    final first = _first;
    if (first == null) {
      setState(() {
        _first = pin;
        _mismatch = null;
      });
      return null;
    }
    if (pin != first) {
      setState(() {
        _first = null;
        _mismatch = 'Those were different. Choose your PIN again.';
      });
      return null;
    }
    Navigator.of(context).pop<PinChoice>((pin: pin));
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final again = _first != null;
    final mismatch = _mismatch;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set a 4-digit PIN'),
        actions: [
          if (widget.skippable)
            TextButton(
              onPressed: () => Navigator.of(context).pop<PinChoice>((pin: null)),
              child: const Text('Skip'),
            ),
        ],
      ),
      body: SafeArea(
        child: PinPad(
          // A fresh pad for each entry, so no dots carry over.
          key: ValueKey(again),
          header: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              children: [
                Icon(Icons.pin_outlined, size: 56, color: scheme.primary),
                const SizedBox(height: 12),
                Text(
                  again ? 'Type it again' : 'Choose 4 numbers',
                  textAlign: TextAlign.center,
                  style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  mismatch ??
                      'Sign in on this phone with these instead of your password. After 5 wrong tries, '
                          'you will need your password.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: mismatch != null ? scheme.error : null),
                ),
              ],
            ),
          ),
          onComplete: _entered,
        ),
      ),
    );
  }
}
