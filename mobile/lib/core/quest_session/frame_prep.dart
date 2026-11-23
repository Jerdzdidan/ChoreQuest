import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

/// One camera frame as an Android phone camera delivers it: YUV 4:2:0, a
/// full-size luma plane and two quarter-size chroma planes, each with its
/// own row stride, the chroma with a pixel stride (1 for planar, 2 for
/// interleaved).
class YuvFrame {
  const YuvFrame({
    required this.width,
    required this.height,
    required this.y,
    required this.u,
    required this.v,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    this.rotation = 0,
  });

  final int width;
  final int height;
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;

  /// Degrees clockwise the frame must turn to be upright: the sensor's
  /// orientation on a phone held upright, as the session locks it.
  final int rotation;
}

/// MobileNetV2's input from a frame (LS-3): the centre square, turned
/// upright, resized to [size] x [size] by nearest sampling, RGB scaled from
/// 0..255 to -1..1. Row by row from the top, three values a pixel.
///
/// Pure, with no Flutter in it, so it runs in a background isolate and in a
/// plain test alike.
Float32List prepareYuv(YuvFrame frame, int size) {
  final side = frame.width < frame.height ? frame.width : frame.height;
  final left = (frame.width - side) ~/ 2;
  final top = (frame.height - side) ~/ 2;
  final out = Float32List(size * size * 3);
  var o = 0;

  for (var oy = 0; oy < size; oy++) {
    for (var ox = 0; ox < size; ox++) {
      // A point of the upright square, then the same point in the sensor's
      // square before turning.
      final ux = (ox * side) ~/ size;
      final uy = (oy * side) ~/ size;
      final (sx, sy) = switch (frame.rotation % 360) {
        90 => (uy, side - 1 - ux),
        180 => (side - 1 - ux, side - 1 - uy),
        270 => (side - 1 - uy, ux),
        _ => (ux, uy),
      };
      final x = left + sx;
      final y = top + sy;

      final luma = frame.y[y * frame.yRowStride + x];
      final chroma = (y >> 1) * frame.uvRowStride + (x >> 1) * frame.uvPixelStride;
      final cb = frame.u[chroma] - 128;
      final cr = frame.v[chroma] - 128;

      final r = luma + 1.402 * cr;
      final g = luma - 0.344136 * cb - 0.714136 * cr;
      final b = luma + 1.772 * cb;
      out[o++] = _scaled(r);
      out[o++] = _scaled(g);
      out[o++] = _scaled(b);
    }
  }
  return out;
}

double _scaled(double channel) {
  final clamped = channel < 0 ? 0.0 : (channel > 255 ? 255.0 : channel);
  return clamped / 127.5 - 1;
}

/// A small grey picture of a frame, [side] x [side], for telling whether
/// the camera is being held still.
Uint8List lumaThumbnail(YuvFrame frame, {int side = 16}) {
  final out = Uint8List(side * side);
  for (var ty = 0; ty < side; ty++) {
    for (var tx = 0; tx < side; tx++) {
      final x = (tx * frame.width) ~/ side;
      final y = (ty * frame.height) ~/ side;
      out[ty * side + tx] = frame.y[y * frame.yRowStride + x];
    }
  }
  return out;
}

/// Tells when the picture has been steady long enough for the Before photo
/// (LS-7): every change between one thumbnail and the next small, for
/// [steadyFor] together.
class SteadyWatch {
  SteadyWatch({this.steadyFor = const Duration(seconds: 2), this.threshold = 6});

  final Duration steadyFor;

  /// The largest mean change per pixel, out of 255, that still counts as
  /// still.
  final double threshold;

  Uint8List? _last;
  Duration? _stillSince;

  /// Takes one thumbnail at [at]; true once the picture has been steady for
  /// [steadyFor].
  bool add(Uint8List thumbnail, Duration at) {
    final last = _last;
    _last = thumbnail;
    if (last == null || last.length != thumbnail.length) {
      _stillSince = at;
      return false;
    }
    var total = 0;
    for (var i = 0; i < thumbnail.length; i++) {
      total += (thumbnail[i] - last[i]).abs();
    }
    if (total / thumbnail.length > threshold) {
      _stillSince = at;
      return false;
    }
    return at - (_stillSince ?? at) >= steadyFor;
  }
}

/// Prepares frames in one background isolate, so the preview never
/// stutters (LS-3). A frame that arrives while the last is still being
/// prepared is dropped, never queued: the model wants the newest frame, not
/// a backlog.
class FramePrepWorker {
  FramePrepWorker({required this.size});

  final int size;
  SendPort? _send;
  Isolate? _isolate;
  final _replies = ReceivePort();
  Completer<Float32List>? _pending;

  bool get busy => _pending != null;

  Future<void> start() async {
    final ready = Completer<SendPort>();
    _replies.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is TransferableTypedData) {
        final done = _pending;
        _pending = null;
        done?.complete(message.materialize().asFloat32List());
      }
    });
    _isolate = await Isolate.spawn(_work, (_replies.sendPort, size));
    _send = await ready.future;
  }

  /// The prepared frame, or null when the worker was busy and dropped it.
  Future<Float32List?> prepare(YuvFrame frame) {
    final send = _send;
    if (send == null || busy) return Future.value(null);
    final done = _pending = Completer<Float32List>();
    send.send([
      frame.width,
      frame.height,
      TransferableTypedData.fromList([frame.y]),
      TransferableTypedData.fromList([frame.u]),
      TransferableTypedData.fromList([frame.v]),
      frame.yRowStride,
      frame.uvRowStride,
      frame.uvPixelStride,
      frame.rotation,
    ]);
    return done.future;
  }

  void stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _replies.close();
    _pending = null;
  }

  static void _work((SendPort, int) setup) {
    final (reply, size) = setup;
    final inbox = ReceivePort();
    reply.send(inbox.sendPort);
    inbox.listen((message) {
      final m = message as List;
      final frame = YuvFrame(
        width: m[0] as int,
        height: m[1] as int,
        y: (m[2] as TransferableTypedData).materialize().asUint8List(),
        u: (m[3] as TransferableTypedData).materialize().asUint8List(),
        v: (m[4] as TransferableTypedData).materialize().asUint8List(),
        yRowStride: m[5] as int,
        uvRowStride: m[6] as int,
        uvPixelStride: m[7] as int,
        rotation: m[8] as int,
      );
      final prepared = prepareYuv(frame, size);
      reply.send(TransferableTypedData.fromList([prepared.buffer.asUint8List()]));
    });
  }
}
