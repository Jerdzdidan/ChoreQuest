import 'package:flutter/material.dart';

/// The faces a child chooses between. The server stores only the key, so the
/// artwork can change without a migration.
///
/// Animals rather than initials: the youngest users cannot yet reliably read
/// their own name, but every one of them can find their fox.
class AvatarStyle {
  const AvatarStyle(this.emoji, this.background, {this.unlockLevel = 1});

  final String emoji;
  final Color background;

  /// The level a child must reach before they can pick this animal. Level 1
  /// means from the start. Levels come from lib/shared/leveling.dart.
  final int unlockLevel;
}

const avatars = <String, AvatarStyle>{
  'fox': AvatarStyle('🦊', Color(0xFFFFE3CC)),
  'owl': AvatarStyle('🦉', Color(0xFFEBDFCB)),
  'cat': AvatarStyle('🐱', Color(0xFFFFF1C2)),
  'dog': AvatarStyle('🐶', Color(0xFFE9DCD2)),
  'frog': AvatarStyle('🐸', Color(0xFFD7F0C9)),
  'panda': AvatarStyle('🐼', Color(0xFFE4E7EA), unlockLevel: 3),
  'penguin': AvatarStyle('🐧', Color(0xFFD5E6F5)),
  'lion': AvatarStyle('🦁', Color(0xFFFFE7B8), unlockLevel: 2),
  'rabbit': AvatarStyle('🐰', Color(0xFFF7DDE8)),
  'bear': AvatarStyle('🐻', Color(0xFFEBDCCB)),
  'tiger': AvatarStyle('🐯', Color(0xFFFFDDB8), unlockLevel: 4),
  'koala': AvatarStyle('🐨', Color(0xFFDDE3E8)),
};

AvatarStyle avatarFor(String key) =>
    avatars[key] ?? const AvatarStyle('🙂', Color(0xFFE2EFE7));

/// "fox" as "Fox", for labels and screen readers.
String avatarName(String key) =>
    key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

/// Whether this animal can be picked at [level].
///
/// An animal a child already has is always theirs to keep: a lock added
/// later never takes it away, so pass it as [current].
bool canPickAvatar(String key, {required int level, String? current}) =>
    key == current || avatarFor(key).unlockLevel <= level;

class AvatarBadge extends StatelessWidget {
  const AvatarBadge(this.avatarKey, {super.key, this.size = 72});

  final String avatarKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = avatarFor(avatarKey);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: style.background, shape: BoxShape.circle),
      child: Text(style.emoji, style: TextStyle(fontSize: size * 0.55)),
    );
  }
}
