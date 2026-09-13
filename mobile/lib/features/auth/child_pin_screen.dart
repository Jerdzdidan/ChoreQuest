import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/session/session_controller.dart';
import '../../shared/avatars.dart';
import 'household_api.dart';

/// Four digits, on keys big enough for a four-year-old's finger.
///
/// It submits on the fourth digit instead of waiting for an OK button, which
/// is one less thing to find. A wrong PIN clears the dots and says so; the
/// words come from the server, which already phrases them for a child.
class ChildPinScreen extends ConsumerStatefulWidget {
  const ChildPinScreen({
    super.key,
    required this.profile,
    required this.householdCode,
  });

  final RosterChild profile;
  final String householdCode;

  @override
  ConsumerState<ChildPinScreen> createState() => _ChildPinScreenState();
}

class _ChildPinScreenState extends ConsumerState<ChildPinScreen> {
  static const _length = 4;

  String _pin = '';
  bool _busy = false;
  String? _message;

  void _press(String digit) {
    if (_busy || _pin.length >= _length) return;
    setState(() {
      _pin += digit;
      _message = null;
    });
    if (_pin.length == _length) _submit();
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).signInChild(
            householdCode: widget.householdCode,
            childId: widget.profile.id,
            pin: _pin,
          );
      // On success the root opens this child's home and discards this screen.
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _message = e.message;
          _pin = '';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final message = _message;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        // Scrolls on short screens instead of overflowing. The phones this
        // study targets include small, low-end handsets.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    AvatarBadge(widget.profile.avatar, size: 96),
                    const SizedBox(height: 12),
                    Text(
                      widget.profile.name,
                      style: text.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 24),
                    Semantics(
                      label: '${_pin.length} of $_length numbers entered',
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _length; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 10),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < _pin.length
                                    ? scheme.primary
                                    : Colors.transparent,
                                border:
                                    Border.all(color: scheme.primary, width: 2.5),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 72,
                      child: Center(
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : message == null
                                ? null
                                : Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                    ),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        message,
                                        textAlign: TextAlign.center,
                                        style: text.titleMedium
                                            ?.copyWith(color: scheme.error),
                                      ),
                                    ),
                                  ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                      child: Column(
                        children: [
                          for (final row in const [
                            ['1', '2', '3'],
                            ['4', '5', '6'],
                            ['7', '8', '9'],
                          ])
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                for (final digit in row)
                                  _Key(label: digit, onTap: () => _press(digit)),
                              ],
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              const SizedBox(width: _Key.size),
                              _Key(label: '0', onTap: () => _press('0')),
                              _Key(
                                icon: Icons.backspace_outlined,
                                semanticLabel: 'Delete',
                                onTap: _backspace,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.onTap,
    this.label,
    this.icon,
    this.semanticLabel,
  });

  static const double size = 72;

  final VoidCallback onTap;
  final String? label;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyph = icon;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: glyph == null
              ? scheme.surfaceContainerHighest
              : Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: glyph != null
                  ? Icon(glyph, size: 30, semanticLabel: semanticLabel)
                  : Text(
                      label ?? '',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
