import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_exception.dart';
import 'inline_error.dart';

/// Loading, failed, or loaded, for anything fetched from the server.
///
/// Renders no scrollable of its own, so it sits inside a screen's list. Data
/// already shown stays shown when a refresh fails, so a dropped connection
/// does not blank a list someone was reading.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return builder(context, value.requireValue);

    if (value.hasError) {
      final error = value.error;
      final retry = onRetry;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineError(
            error is ApiException
                ? error.message
                : 'Something went wrong while loading this.',
          ),
          if (retry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: retry, child: const Text('Try again')),
          ],
        ],
      );
    }

    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
