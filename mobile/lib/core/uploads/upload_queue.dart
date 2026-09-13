import 'dart:convert';
import 'dart:io';

import 'pending_upload.dart';

/// Photos that have not reached the server yet, kept on the phone.
///
/// An upload is written here before its first attempt and removed only once
/// the server has answered for it. A dropped connection, a killed app or a
/// flat battery therefore leaves a photo waiting rather than lost.
///
/// The index is replaced by writing a fresh file and renaming it over the old
/// one. A crash part-way through a write leaves the previous index whole,
/// never half a file.
class UploadQueue {
  UploadQueue(this.root);

  final Directory root;

  /// Chains every read-modify-write, so two callers can never interleave and
  /// silently drop an entry.
  Future<void> _tail = Future.value();

  String get _sep => Platform.pathSeparator;
  File get _index => File('${root.path}${_sep}pending_uploads.json');
  Directory get _photos => Directory('${root.path}${_sep}pending_photos');

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<List<PendingUpload>> all() => _exclusive(_read);

  Future<List<PendingUpload>> forChild(int childId) async =>
      (await all()).where((u) => u.childId == childId).toList();

  /// Copies the photo into the queue's own folder before recording it. The
  /// camera writes to a cache directory that Android may clear at any time,
  /// including while a photo is still waiting for a connection.
  ///
  /// Enqueueing a token that is already waiting changes nothing.
  Future<PendingUpload> enqueue({
    required String clientToken,
    required int childId,
    required int assignmentId,
    required String choreName,
    required String sourcePhotoPath,
    String? label,
    double? confidence,
    String? modelVersion,
    int? inferenceMs,
  }) {
    return _exclusive(() async {
      final items = await _read();
      final existing = items.where((u) => u.clientToken == clientToken);
      if (existing.isNotEmpty) return existing.first;

      await _photos.create(recursive: true);
      final stored = '${_photos.path}$_sep$clientToken.jpg';
      if (File(sourcePhotoPath).absolute.path != File(stored).absolute.path) {
        await File(sourcePhotoPath).copy(stored);
      }

      final upload = PendingUpload(
        clientToken: clientToken,
        childId: childId,
        assignmentId: assignmentId,
        choreName: choreName,
        photoPath: stored,
        createdAt: DateTime.now(),
        label: label,
        confidence: confidence,
        modelVersion: modelVersion,
        inferenceMs: inferenceMs,
      );
      await _write([...items, upload]);
      return upload;
    });
  }

  Future<void> recordFailure(String clientToken, String message) {
    return _exclusive(() async {
      final items = await _read();
      final index = items.indexWhere((u) => u.clientToken == clientToken);
      if (index < 0) return;
      items[index] = items[index].failedAgain(message);
      await _write(items);
    });
  }

  /// Forgets an upload and deletes its photo. Called once the server has
  /// answered for it, whether it accepted the photo or refused it for good.
  Future<void> remove(String clientToken) {
    return _exclusive(() async {
      final items = await _read();
      final leaving = items.where((u) => u.clientToken == clientToken).toList();
      if (leaving.isEmpty) return;

      await _write(items.where((u) => u.clientToken != clientToken).toList());
      for (final upload in leaving) {
        try {
          await File(upload.photoPath).delete();
        } on FileSystemException {
          // Already gone.
        }
      }
    });
  }

  Future<List<PendingUpload>> _read() async {
    final index = _index;
    if (!await index.exists()) return [];

    try {
      final raw = jsonDecode(await index.readAsString()) as List;
      return raw.cast<Map<String, dynamic>>().map(PendingUpload.fromJson).toList();
    } catch (_) {
      // Unreadable. Moved aside rather than deleted, so the photos it listed
      // can still be found by hand instead of vanishing without a trace.
      await index.rename(
        '${index.path}.unreadable-${DateTime.now().millisecondsSinceEpoch}',
      );
      return [];
    }
  }

  Future<void> _write(List<PendingUpload> items) async {
    await root.create(recursive: true);
    final temp = File('${_index.path}.tmp');
    await temp.writeAsString(
      jsonEncode([for (final upload in items) upload.toJson()]),
      flush: true,
    );
    await temp.rename(_index.path);
  }
}
