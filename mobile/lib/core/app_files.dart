import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app's private files folder, set in main(): what Android neither
/// clears like a cache nor lets other apps read. The upload queue, the last
/// model config and the record of celebrations already shown live here.
/// The system's temporary folder stands in outside main(), as in tests.
final appFilesProvider = Provider<Directory>((ref) => Directory.systemTemp);

/// A file in the app's private folder.
File appFile(Directory base, String name) => File('${base.path}${Platform.pathSeparator}$name');
