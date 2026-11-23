import 'package:flutter/material.dart';

import '../core/models/chore.dart';

/// How a chore is checked, as a small tag beside its name: "Motion-checked"
/// when the movement model watches the quest, "Manual check" when only the
/// grown-up does (every custom chore). Icon and words both, so it reads
/// without colour.
class VerificationTag extends StatelessWidget {
  const VerificationTag(this.mode, {super.key});

  final VerificationMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (fill, ink, icon) = switch (mode) {
      VerificationMode.motion => (scheme.primaryContainer, scheme.onPrimaryContainer, Icons.directions_run_rounded),
      VerificationMode.manual => (scheme.tertiaryContainer, scheme.onTertiaryContainer, Icons.visibility_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              mode.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
