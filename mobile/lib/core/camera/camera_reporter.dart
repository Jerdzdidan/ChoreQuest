import 'dart:async';

import '../models/camera.dart';

/// Tells the server every camera the child's phone can see (DV-9), so the
/// parent's phone offers a third-party camera only while one is connected
/// (PS-6). Sent at app start and at every return to the app, a moment after
/// a camera comes or goes, and every few minutes in between: the server
/// counts a camera as connected only for ten minutes after the phone last
/// said so.
class CameraReporter {
  CameraReporter({
    required this.listers,
    required this.report,
    this.heartbeat = const Duration(minutes: 5),
    this.settle = const Duration(seconds: 2),
  });

  /// Each kind's list of cameras now.
  final List<Future<List<ReportedCamera>> Function()> listers;

  /// POST /my/cameras.
  final Future<void> Function(List<ReportedCamera> cameras) report;

  /// How often the same list is sent again, inside the server's ten minutes.
  final Duration heartbeat;

  /// How long to wait after a change: a USB camera takes a moment to appear,
  /// and one plug-in sends several signals.
  final Duration settle;

  List<ReportedCamera>? _sent;
  List<ReportedCamera>? _latest;
  final _updates = StreamController<List<ReportedCamera>>.broadcast();
  StreamSubscription<void>? _changes;
  Timer? _beat;
  Timer? _settling;

  /// What was last sent, or null before the first report went.
  List<ReportedCamera>? get sent => _sent;

  /// What the last look found, sent or not.
  List<ReportedCamera>? get latest => _latest;

  /// Every look's list, for a screen showing the cameras as they come and
  /// go.
  Stream<List<ReportedCamera>> get updates => _updates.stream;

  /// Lists every camera now and sends the list if it changed since the last
  /// report, or always when [force]. A report that fails is tried at the
  /// next one.
  Future<List<ReportedCamera>> refresh({bool force = false}) async {
    final cameras = <ReportedCamera>[];
    for (final list in listers) {
      try {
        cameras.addAll(await list());
      } catch (_) {
        // This kind cannot say right now; the others still count.
      }
    }
    _latest = cameras;
    if (!_updates.isClosed) _updates.add(cameras);
    if (force || !_same(cameras, _sent)) {
      try {
        await report(cameras);
        _sent = cameras;
      } catch (_) {
        // Offline: the next change or heartbeat tries again.
      }
    }
    return cameras;
  }

  /// Reports now, then on every change and heartbeat until [stop].
  void start(Stream<void> changes) {
    stop();
    unawaited(refresh(force: true));
    _changes = changes.listen((_) {
      _settling?.cancel();
      _settling = Timer(settle, () => unawaited(refresh()));
    }, onError: (_) {});
    _beat = Timer.periodic(heartbeat, (_) => unawaited(refresh(force: true)));
  }

  void stop() {
    unawaited(_changes?.cancel());
    _changes = null;
    _beat?.cancel();
    _beat = null;
    _settling?.cancel();
    _settling = null;
  }

  /// Stops for good.
  void close() {
    stop();
    unawaited(_updates.close());
  }

  static bool _same(List<ReportedCamera> a, List<ReportedCamera>? b) {
    if (b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final (x, y) = (a[i], b[i]);
      if (x.key != y.key || x.kind != y.kind || x.label != y.label || x.connected != y.connected) return false;
    }
    return true;
  }
}
