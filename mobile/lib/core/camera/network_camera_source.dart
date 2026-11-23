import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart' show CameraException;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/camera.dart';
import '../quest_session/frame_prep.dart';
import 'camera_source.dart';
import 'network_camera.dart';
import 'session_camera.dart';

/// The network cameras added on this phone, logins included, in the phone's
/// secure storage (DV-11). Kept in memory after the first read.
class NetworkCameraStore {
  NetworkCameraStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'network_cameras';

  final FlutterSecureStorage _storage;
  List<NetworkCameraConfig>? _cameras;

  Future<List<NetworkCameraConfig>> load() async {
    final known = _cameras;
    if (known != null) return known;
    try {
      final raw = await _storage.read(key: _key);
      return _cameras = [
        for (final camera in (jsonDecode(raw ?? '[]') as List).cast<Map<String, dynamic>>()) NetworkCameraConfig.fromJson(camera),
      ];
    } catch (_) {
      // Nothing saved, or storage this phone cannot read: none.
      return _cameras = const [];
    }
  }

  Future<void> save(List<NetworkCameraConfig> cameras) async {
    await _storage.write(key: _key, value: jsonEncode([for (final camera in cameras) camera.toJson()]));
    _cameras = List.unmodifiable(cameras);
  }
}

/// CCTV and IP cameras added by address (DV-11). One counts as connected
/// only once it has answered with a picture, tried again every
/// [recheck], so one switched off or unplugged shows as gone within about
/// half a minute.
class NetworkCameraSource implements QuestCameraSource {
  NetworkCameraSource({
    required this.store,
    NetworkCameraClient? client,
    this.recheck = const Duration(seconds: 15),
  }) : client = client ?? NetworkCameraClient();

  final NetworkCameraStore store;
  final NetworkCameraClient client;
  final Duration recheck;

  final _edited = StreamController<void>.broadcast();
  final _answers = <String, ({bool ok, DateTime at})>{};
  var _known = <String, NetworkCameraConfig>{};

  @override
  CameraKind get kind => CameraKind.network;

  @override
  Future<List<ReportedCamera>> list() async {
    final cameras = await store.load();
    _known = {for (final camera in cameras) camera.id: camera};
    final answered = await Future.wait([for (final camera in cameras) _hasAnswered(camera)]);
    return [
      for (var i = 0; i < cameras.length; i++)
        ReportedCamera(key: cameras[i].id, kind: CameraKind.network, label: cameras[i].name, connected: answered[i]),
    ];
  }

  /// Whether it answered lately, asking again if not within the last ten
  /// seconds.
  Future<bool> _hasAnswered(NetworkCameraConfig camera) async {
    final last = _answers[camera.id];
    if (last != null && DateTime.now().difference(last.at) < const Duration(seconds: 10)) return last.ok;
    final probe = await client.probe(camera, timeout: const Duration(seconds: 4));
    _answers[camera.id] = (ok: probe.ok, at: DateTime.now());
    return probe.ok;
  }

  /// Adds or replaces a camera, by its id.
  Future<void> put(NetworkCameraConfig camera) async {
    final cameras = [for (final known in await store.load()) if (known.id != camera.id) known, camera];
    await store.save(cameras);
    _answers.remove(camera.id);
    _edited.add(null);
  }

  Future<void> remove(String id) async {
    await store.save([for (final known in await store.load()) if (known.id != id) known]);
    _answers.remove(id);
    _edited.add(null);
  }

  /// On every add or remove, and every [recheck] while there is a camera to
  /// try.
  @override
  Stream<void> get changes {
    Timer? timer;
    StreamSubscription<void>? edits;
    late final StreamController<void> out;
    out = StreamController<void>(
      onListen: () {
        edits = _edited.stream.listen(out.add);
        timer = Timer.periodic(recheck, (_) async {
          if ((await store.load()).isNotEmpty && !out.isClosed) out.add(null);
        });
      },
      onCancel: () {
        timer?.cancel();
        return edits?.cancel();
      },
    );
    return out.stream;
  }

  @override
  SessionCamera open(String key) =>
      NetworkSessionCamera(_known[key] ?? NetworkCameraConfig(id: key, name: 'Camera', url: ''), client);
}

/// A network camera for a quest session: its pictures shown as they come,
/// and turned into the same frames a phone camera gives, so the same
/// detector watches it with no change. It does not flip.
class NetworkSessionCamera implements SessionCamera {
  NetworkSessionCamera(this.camera, this.client, {Future<(Uint8List, int, int)> Function(Uint8List picture)? decode})
      : _decode = decode ?? _decodeSmall;

  final NetworkCameraConfig camera;
  final NetworkCameraClient client;
  final Future<(Uint8List, int, int)> Function(Uint8List picture) _decode;

  /// Frames go to the detector no faster than this: about the model's
  /// rate, however fast the camera streams.
  static const frameGap = Duration(milliseconds: 200);

  final _latest = ValueNotifier<Uint8List?>(null);
  final _sinceFrame = Stopwatch();
  StreamSubscription<Uint8List>? _pictures;
  void Function(YuvFrame frame)? _onFrame;
  var _decoding = false;

  @override
  String get label => 'network';

  @override
  bool get canFlip => false;

  @override
  bool get isOpen => _pictures != null;

  @override
  Future<void> open() async {
    final probe = await client.probe(camera);
    if (!probe.ok) throw CameraException('NoCamera', probe.problem);
    _latest.value = probe.picture;
    _pictures = client.pictures(camera, probe.feed!).listen(_onPicture, onError: (_) {
      // A dropped picture; the stream keeps trying, and the last one stays
      // on the screen.
    });
  }

  void _onPicture(Uint8List picture) {
    _latest.value = picture;
    final onFrame = _onFrame;
    if (onFrame == null || _decoding) return;
    if (_sinceFrame.isRunning && _sinceFrame.elapsed < frameGap) return;
    _decoding = true;
    _sinceFrame
      ..reset()
      ..start();
    _decode(picture).then((decoded) {
      final (rgba, width, height) = decoded;
      if (_onFrame != null) onFrame(yuvFromRgba(rgba, width, height));
    }).catchError((_) {
      // A picture that would not decode: skip it.
    }).whenComplete(() => _decoding = false);
  }

  /// Decoded small: the model looks at 192 x 192 from the centre.
  static Future<(Uint8List, int, int)> _decodeSmall(Uint8List picture) async {
    final codec = await ui.instantiateImageCodec(picture, targetWidth: 320);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('not decoded');
      return (data.buffer.asUint8List(), image.width, image.height);
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  @override
  Widget preview() => ValueListenableBuilder<Uint8List?>(
        valueListenable: _latest,
        builder: (context, picture, _) => picture == null
            ? const SizedBox.shrink()
            : Image.memory(picture, gaplessPlayback: true, fit: BoxFit.contain),
      );

  @override
  Future<void> flip() async {}

  @override
  Future<void> startFrames(void Function(YuvFrame frame) onFrame) async => _onFrame = onFrame;

  @override
  Future<void> stopFrames() async => _onFrame = null;

  /// The latest picture, saved to the app's cache, never the gallery.
  @override
  Future<String> takeStill() async {
    final picture = _latest.value;
    if (picture == null) throw CameraException('NotOpen', 'No picture from the camera yet.');
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}cq_net_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(picture, flush: true);
    return file.path;
  }

  @override
  Future<void> close() async {
    _onFrame = null;
    final pictures = _pictures;
    _pictures = null;
    await pictures?.cancel();
  }
}
