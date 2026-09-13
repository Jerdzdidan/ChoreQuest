import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/session/session_controller.dart';

/// A chore photo, fetched with the signed-in parent's token.
///
/// The server never serves these publicly. It hands a photo only to the parent
/// whose household it belongs to, so every request carries that parent's
/// sign-in. Nothing is saved to the phone's storage: the decoded image lives in
/// memory only.
class SubmissionPhoto extends ConsumerWidget {
  const SubmissionPhoto({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.decodeWidth,
    this.semanticLabel,
  });

  final String url;
  final BoxFit fit;

  /// Decodes at about this many pixels across, so a list of thumbnails does
  /// not hold full-size photos in memory on a phone with little of it.
  final int? decodeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = switch (ref.watch(sessionProvider)) {
      AsyncData(:final value) => value.token,
      _ => null,
    };
    final scheme = Theme.of(context).colorScheme;

    Widget placeholder(IconData icon) => ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Center(child: Icon(icon, color: scheme.onSurfaceVariant)),
        );

    if (token == null) return placeholder(Icons.lock_outline);

    return Image.network(
      url,
      headers: {'Authorization': 'Bearer $token'},
      fit: fit,
      cacheWidth: decodeWidth,
      semanticLabel: semanticLabel,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (context, error, stackTrace) =>
          placeholder(Icons.broken_image_outlined),
    );
  }
}
