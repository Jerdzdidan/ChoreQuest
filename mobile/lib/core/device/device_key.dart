import 'dart:io';

import '../uploads/client_token.dart';

/// A random name for this install of the app, made once and kept in the
/// app's own files: what the server files a phone's camera list under
/// (BE-8). It says nothing about the phone or the child.
class DeviceKeyStore {
  DeviceKeyStore(this.file);

  final File file;
  String? _key;

  Future<String> read() async {
    final known = _key;
    if (known != null) return known;
    try {
      final saved = (await file.readAsString()).trim();
      if (saved.isNotEmpty) return _key = saved;
    } catch (_) {
      // None yet, or unreadable: make a new one.
    }
    final made = newClientToken();
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(made, flush: true);
    } catch (_) {
      // Kept for this run only; the next run makes another.
    }
    return _key = made;
  }
}
