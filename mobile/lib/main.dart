import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/notifications/local_notifier.dart';
import 'core/uploads/upload_queue.dart';
import 'features/child/child_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Photos waiting for a connection live in the app's private files, which
  // Android neither clears like a cache nor lets other apps read.
  Directory base;
  try {
    base = await getApplicationSupportDirectory();
  } catch (error) {
    // Unheard of on Android, but a phone that cannot say where its files go
    // should still open. Saved photos then live in the cache instead.
    debugPrint('App files folder unavailable: $error');
    base = Directory.systemTemp;
  }
  final uploads =
      UploadQueue(Directory('${base.path}${Platform.pathSeparator}uploads'));

  // Notifications are a convenience. If they cannot start, the app runs
  // without them rather than not at all.
  final notifier = await LocalNotifier.start();

  runApp(
    ProviderScope(
      overrides: [
        uploadQueueProvider.overrideWithValue(uploads),
        if (notifier != null) appNotifierProvider.overrideWithValue(notifier),
      ],
      child: const ChoreQuestApp(),
    ),
  );
}
