import 'package:flutter/material.dart';

import '../../shared/avatars.dart';

/// One face to tap in a "Who are you?" grid, for a child or a grown-up.
class ProfileTile extends StatelessWidget {
  const ProfileTile({super.key, required this.avatar, required this.name, required this.onTap});

  final String avatar;
  final String name;
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
            AvatarBadge(avatar, size: 96),
            const SizedBox(height: 12),
            Text(
              name,
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
