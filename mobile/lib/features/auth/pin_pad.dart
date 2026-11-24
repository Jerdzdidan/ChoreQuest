import 'package:flutter/material.dart';

/// Four digits, on keys big enough for a four-year-old's finger: the child's
/// PIN, the grown-up's PIN (PA-5), and choosing a new one.
///
/// It submits on the fourth digit instead of waiting for an OK button, which
/// is one less thing to find. [onComplete] returns a message to show, which
/// clears the dots for another go, or null when the PIN was taken.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.header,
    required this.onComplete,
    this.footer,
  });

  static const length = 4;

  /// Above the dots: whose PIN it is, or what to type.
  final Widget header;

  final Future<String?> Function(String pin) onComplete;

  /// Below the keys, such as a way to use the password instead.
  final Widget? footer;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  bool _busy = false;
  String? _message;

  void _press(String digit) {
    if (_busy || _pin.length >= PinPad.length) return;
    setState(() {
      _pin += digit;
      _message = null;
    });
    if (_pin.length == PinPad.length) _submit();
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final message = await widget.onComplete(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (message != null) {
        _message = message;
        _pin = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final message = _message;
    final footer = widget.footer;

    // Scrolls on short screens instead of overflowing. The phones this
    // study targets include small, low-end handsets.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              children: [
                widget.header,
                const SizedBox(height: 24),
                Semantics(
                  label: '${_pin.length} of ${PinPad.length} numbers entered',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < PinPad.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _pin.length ? scheme.primary : Colors.transparent,
                            border: Border.all(color: scheme.primary, width: 2.5),
                          ),
                        ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Center(
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : message == null
                            ? null
                            : Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    message,
                                    textAlign: TextAlign.center,
                                    style: text.titleMedium?.copyWith(color: scheme.error),
                                  ),
                                ),
                              ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
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
                            for (final digit in row) _Key(label: digit, onTap: () => _press(digit)),
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
                ?footer,
                const SizedBox(height: 8),
              ],
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
          color: glyph == null ? scheme.surfaceContainerHighest : Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Center(
              child: glyph != null
                  ? Icon(glyph, size: 30, semanticLabel: semanticLabel)
                  : Text(
                      label ?? '',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A face and a name above the dots: whose PIN this is.
class PinHeader extends StatelessWidget {
  const PinHeader({super.key, required this.avatar, required this.name, this.hint});

  final Widget avatar;
  final String name;

  /// A line under the name, such as "Type your PIN".
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hint = this.hint;
    return Column(
      children: [
        avatar,
        const SizedBox(height: 12),
        Text(
          name,
          textAlign: TextAlign.center,
          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint, textAlign: TextAlign.center, style: text.bodyLarge),
        ],
      ],
    );
  }
}
