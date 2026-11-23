import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../quest_session/frame_prep.dart';

/// A CCTV or IP camera a grown-up added on the child's phone by its address
/// (DV-11). The login, if it has one, is kept in the phone's secure storage
/// with the rest, never sent to the ChoreQuest server.
class NetworkCameraConfig {
  const NetworkCameraConfig({
    required this.id,
    required this.name,
    required this.url,
    this.username = '',
    this.password = '',
  });

  factory NetworkCameraConfig.fromJson(Map<String, dynamic> json) => NetworkCameraConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
      );

  /// The key the server and the schedule know it by: net- and a random part.
  final String id;

  /// What the parent sees, such as "Kitchen CCTV".
  final String name;

  /// A snapshot (one JPEG per request) or MJPEG stream address.
  final String url;
  final String username;
  final String password;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'username': username,
        'password': password,
      };
}

/// How a camera sends pictures over HTTP: one JPEG per request, or an
/// endless multipart stream of them.
enum NetworkFeed { snapshot, mjpeg }

/// What a camera did when tried: a first picture and how it sends them, or
/// a sentence for the grown-up saying what went wrong.
class NetworkProbe {
  const NetworkProbe.answered(this.feed, Uint8List this.picture) : problem = null;
  const NetworkProbe.failed(String this.problem)
      : feed = null,
        picture = null;

  final NetworkFeed? feed;
  final Uint8List? picture;
  final String? problem;

  bool get ok => problem == null;
}

/// Talks to network cameras over plain HTTP, with no plugin: a snapshot
/// address is asked for a picture about twice a second; an MJPEG address is
/// read as it streams and split into pictures. RTSP is not spoken.
class NetworkCameraClient {
  NetworkCameraClient({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));

  final Dio _dio;

  /// Biggest picture accepted, against an address that streams something
  /// else forever.
  static const maxPicture = 8 * 1024 * 1024;

  Options _options(NetworkCameraConfig camera, Duration timeout) => Options(
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        receiveTimeout: timeout,
        headers: {
          if (camera.username.isNotEmpty)
            'Authorization': 'Basic ${base64Encode(utf8.encode('${camera.username}:${camera.password}'))}',
        },
      );

  /// Tries the camera once: does it answer, with a picture, and how.
  Future<NetworkProbe> probe(NetworkCameraConfig camera, {Duration timeout = const Duration(seconds: 5)}) async {
    final address = Uri.tryParse(camera.url.trim());
    if (address == null || address.host.isEmpty) {
      return const NetworkProbe.failed("That doesn't look like a camera address. It starts with http://");
    }
    if (address.scheme.startsWith('rtsp')) {
      return const NetworkProbe.failed(
          "ChoreQuest can't use RTSP addresses. Look in the camera's settings for its snapshot (JPEG) or MJPEG address.");
    }
    if (address.scheme != 'http' && address.scheme != 'https') {
      return const NetworkProbe.failed("That doesn't look like a camera address. It starts with http://");
    }
    try {
      final response = await _dio
          .getUri<ResponseBody>(address, options: _options(camera, timeout))
          .timeout(timeout);
      final status = response.statusCode ?? 0;
      if (status == 401 || status == 403) {
        unawaited(_drain(response));
        final asks = response.headers.value('www-authenticate') ?? '';
        return NetworkProbe.failed(asks.toLowerCase().startsWith('digest')
            ? "This camera asks for a kind of login ChoreQuest can't do (Digest). Turn on Basic login in the camera's settings, or use an address without a login."
            : 'The camera turned down that name and password.');
      }
      if (status != 200) {
        unawaited(_drain(response));
        return NetworkProbe.failed('The camera answered with an error ($status).');
      }
      final type = (response.headers.value('content-type') ?? '').toLowerCase();
      final body = response.data!.stream;
      if (type.startsWith('image/')) {
        return NetworkProbe.answered(NetworkFeed.snapshot, await _whole(body).timeout(timeout));
      }
      if (type.startsWith('multipart/')) {
        final first = await _split(body).first.timeout(timeout);
        return NetworkProbe.answered(NetworkFeed.mjpeg, first);
      }
      unawaited(_drain(response));
      return const NetworkProbe.failed("That address didn't send a picture. Use the camera's snapshot (JPEG) or MJPEG address.");
    } on TimeoutException {
      return const NetworkProbe.failed("The camera didn't answer. Check it is switched on and on the same Wi-Fi.");
    } on DioException {
      return const NetworkProbe.failed("The camera didn't answer. Check it is switched on and on the same Wi-Fi.");
    } on StateError {
      return const NetworkProbe.failed("That address didn't send a picture. Use the camera's snapshot (JPEG) or MJPEG address.");
    }
  }

  /// Pictures from the camera until the listener stops: for a snapshot
  /// address one about every [interval], for a stream as fast as it sends.
  /// A failed fetch is an error on the stream, and it carries on trying.
  Stream<Uint8List> pictures(
    NetworkCameraConfig camera,
    NetworkFeed feed, {
    Duration interval = const Duration(milliseconds: 500),
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    final address = Uri.parse(camera.url.trim());
    while (true) {
      try {
        final response = await _dio.getUri<ResponseBody>(address, options: _options(camera, timeout)).timeout(timeout);
        if (response.statusCode != 200) {
          unawaited(_drain(response));
          throw StateError('status ${response.statusCode}');
        }
        if (feed == NetworkFeed.snapshot) {
          yield await _whole(response.data!.stream).timeout(timeout);
          await Future<void>.delayed(interval);
        } else {
          yield* _split(response.data!.stream);
          // The stream ended: the camera restarted, or dropped us. Again.
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      } catch (e) {
        yield* Stream<Uint8List>.error(e);
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  static Future<void> _drain(Response<ResponseBody> response) async {
    try {
      await response.data?.stream.drain<void>();
    } catch (_) {}
  }

  static Future<Uint8List> _whole(Stream<Uint8List> body) async {
    final out = BytesBuilder(copy: false);
    await for (final chunk in body) {
      out.add(chunk);
      if (out.length > maxPicture) throw StateError('too big');
    }
    return out.takeBytes();
  }

  static Stream<Uint8List> _split(Stream<Uint8List> body) async* {
    final splitter = JpegSplitter();
    await for (final chunk in body) {
      for (final picture in splitter.add(chunk)) {
        yield picture;
      }
    }
  }
}

/// Splits an MJPEG stream into its pictures by each JPEG's own start and end
/// markers, so the multipart boundaries and headers between them need not
/// be read.
class JpegSplitter {
  final _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  /// Above 0, [_pending] starts with a picture's start marker and its end
  /// marker is not before this index: a big picture arriving in many small
  /// chunks is not searched again from its start each time.
  int _resume = 0;

  List<Uint8List> add(List<int> chunk) {
    _buffer
      ..add(_pending)
      ..add(chunk);
    var data = _buffer.takeBytes();
    var resume = _resume;
    final pictures = <Uint8List>[];
    while (true) {
      final start = resume > 0 ? 0 : _find(data, 0xD8, 0);
      if (start < 0) {
        // Keep a trailing 0xFF: it may be half of the next start marker.
        data = data.isNotEmpty && data.last == 0xFF ? Uint8List.fromList(const [0xFF]) : Uint8List(0);
        resume = 0;
        break;
      }
      final end = _find(data, 0xD9, resume > 0 ? resume : start + 2);
      if (end < 0) {
        data = Uint8List.sublistView(data, start);
        // Less one byte, which may be half an end marker.
        resume = data.length > 3 ? data.length - 1 : 2;
        if (data.length > NetworkCameraClient.maxPicture) {
          data = Uint8List(0);
          resume = 0;
        }
        break;
      }
      pictures.add(Uint8List.fromList(Uint8List.sublistView(data, start, end + 2)));
      data = Uint8List.sublistView(data, end + 2);
      resume = 0;
    }
    _pending = data;
    _resume = resume;
    return pictures;
  }

  /// Where 0xFF followed by [marker] starts, from [from], or -1.
  static int _find(Uint8List data, int marker, int from) {
    for (var i = from; i + 1 < data.length; i++) {
      if (data[i] == 0xFF && data[i + 1] == marker) return i;
    }
    return -1;
  }
}

/// A decoded picture (RGBA, as Flutter decodes a JPEG) as the YUV 4:2:0
/// frame a phone camera gives, so the same frame preparation and detector
/// take it unchanged. The inverse of frame preparation's own conversion
/// (full-range BT.601, as JPEG uses).
YuvFrame yuvFromRgba(Uint8List rgba, int width, int height) {
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;
  final y = Uint8List(width * height);
  final u = Uint8List(chromaWidth * chromaHeight);
  final v = Uint8List(chromaWidth * chromaHeight);
  int clamp(double value) => value < 0 ? 0 : (value > 255 ? 255 : value.round());
  for (var row = 0; row < height; row++) {
    for (var col = 0; col < width; col++) {
      final at = (row * width + col) * 4;
      final (r, g, b) = (rgba[at], rgba[at + 1], rgba[at + 2]);
      y[row * width + col] = clamp(0.299 * r + 0.587 * g + 0.114 * b);
      if (row.isEven && col.isEven) {
        final c = (row ~/ 2) * chromaWidth + col ~/ 2;
        u[c] = clamp(128 - 0.168736 * r - 0.331264 * g + 0.5 * b);
        v[c] = clamp(128 + 0.5 * r - 0.418688 * g - 0.081312 * b);
      }
    }
  }
  return YuvFrame(
    width: width,
    height: height,
    y: y,
    u: u,
    v: v,
    yRowStride: width,
    uvRowStride: chromaWidth,
    uvPixelStride: 1,
  );
}
