import 'chore_detector.dart';
import 'done_gate.dart';

/// Where a live quest session stands (LS-1).
enum SessionState {
  /// Nothing yet.
  idle,

  /// The alarm is ringing; the child has not tapped Start.
  ringing,

  /// Start tapped: the camera is opening and the Before photo is being taken.
  starting,

  /// Before taken; watching for movement that matches the chore.
  waitingForMovement,

  /// Matching movement seen: the progress ring fills.
  active,

  /// Enough matching movement: the Done button is on the screen.
  doneAvailable,

  /// Done tapped: the After photo is being taken.
  capturingAfter,

  /// Before and After shown side by side, with Send to my grown-up.
  reviewing,

  /// Being handed to the upload queue.
  sending,

  /// Sent, or queued to send when the phone is back online.
  sent,

  /// Something the child cannot fix went wrong, such as a camera that will
  /// not start.
  failed,
}

/// How this session is checked: by the movement model, or by the parent
/// alone (a custom chore, or no model on the phone).
enum CheckMode { motion, manual }

/// Why a quest the model checks went manual.
enum ManualReason {
  /// No model on the phone, or it failed.
  modelUnavailable('model_unavailable'),

  /// The child started without the phone on a strap (CAM-3).
  noStrap('no_strap'),

  /// The phone has no back camera, so nothing can see the child's hands.
  noBackCamera('no_back_camera');

  const ManualReason(this.key);

  /// As the alarm-stop reason and the evidence call it.
  final String key;
}

/// Something the session tells whoever runs it.
sealed class SessionEvent {
  const SessionEvent();
}

class StateChanged extends SessionEvent {
  const StateChanged(this.from, this.to);

  final SessionState from;
  final SessionState to;
}

/// Stop the alarm (DV-6). Fired once per session: at the first movement that
/// matches the chore, or, with no model to wait for, once Start has been
/// tapped and the Before photo taken.
class StopAlarm extends SessionEvent {
  const StopAlarm(this.reason);

  /// movement, before_photo, or why the session went manual
  /// (ManualReason.key).
  final String reason;
}

/// The progress ring's fill, 0 to 1.
class SessionProgress extends SessionEvent {
  const SessionProgress(this.fraction);

  final double fraction;
}

/// A live quest session as a plain state machine (LS-1): no Flutter, no
/// camera, no clock of its own. The clock and the detector's signals are
/// handed in, so it can be driven by made-up events.
///
/// Every change of state goes through [_go], checked against one table,
/// [allowed]: Done is reachable only from doneAvailable, and a call that does
/// not fit the state throws rather than skipping a step.
class QuestSession {
  QuestSession({
    required this.mode,
    required GateThresholds thresholds,
    required this._now,
    this._onEvent,
  }) : gate = DoneGate(thresholds);

  /// The only moves there are: from each state, where it may go next. Any
  /// state but sent may also go to failed.
  static const allowed = <SessionState, Set<SessionState>>{
    SessionState.idle: {SessionState.ringing, SessionState.starting},
    SessionState.ringing: {SessionState.starting},
    SessionState.starting: {SessionState.waitingForMovement, SessionState.doneAvailable},
    SessionState.waitingForMovement: {SessionState.active, SessionState.doneAvailable},
    SessionState.active: {SessionState.doneAvailable},
    SessionState.doneAvailable: {SessionState.capturingAfter},
    SessionState.capturingAfter: {SessionState.reviewing},
    SessionState.reviewing: {SessionState.capturingAfter, SessionState.sending},
    SessionState.sending: {SessionState.sent},
    SessionState.sent: {},
    SessionState.failed: {},
  };

  CheckMode mode;
  final DoneGate gate;
  final DateTime Function() _now;
  final void Function(SessionEvent event)? _onEvent;

  SessionState _state = SessionState.idle;
  SessionState get state => _state;

  DateTime? startedAt;
  DateTime? finishedAt;
  var alarmStopped = false;

  /// Why a session the model would have checked went manual, if it did.
  ManualReason? manualReason;
  String? failure;

  /// The movement model could not run, so the session went manual.
  bool get modelUnavailable => manualReason == ManualReason.modelUnavailable;

  /// Whether the Done button belongs on the screen.
  bool get showsDone => _state == SessionState.doneAvailable;

  void _emit(SessionEvent event) => _onEvent?.call(event);

  void _go(SessionState to) {
    final from = _state;
    final ok = to == SessionState.failed ? from != SessionState.sent : allowed[from]!.contains(to);
    if (!ok) throw StateError('A quest session cannot go from ${from.name} to ${to.name}.');
    _state = to;
    _emit(StateChanged(from, to));
  }

  void _stopAlarm(String reason) {
    if (alarmStopped) return;
    alarmStopped = true;
    _emit(StopAlarm(reason));
  }

  /// The alarm rang (DV-5).
  void ring() => _go(SessionState.ringing);

  /// The child tapped Start the quest. The alarm keeps ringing.
  void start() {
    startedAt = _now();
    _go(SessionState.starting);
  }

  /// The Before photo is taken. With the model, the session now watches for
  /// movement; without one, Done is available straight away and the alarm
  /// stops (LS-11).
  void beforeCaptured() {
    if (mode == CheckMode.manual) {
      _go(SessionState.doneAvailable);
      _stopAlarm(manualReason?.key ?? 'before_photo');
    } else {
      _go(SessionState.waitingForMovement);
    }
  }

  /// One signal from the detector. Ignored outside the watching states, and
  /// once Done is available it still counts towards the evidence.
  void signal(DetectorSignal signal) {
    if (mode != CheckMode.motion) return;
    if (_state != SessionState.waitingForMovement &&
        _state != SessionState.active &&
        _state != SessionState.doneAvailable) {
      return;
    }
    for (final event in gate.feed(signal)) {
      switch (event) {
        case FirstMovement():
          _stopAlarm('movement');
          if (_state == SessionState.waitingForMovement) _go(SessionState.active);
        case Progress(:final fraction):
          _emit(SessionProgress(fraction));
        case DoneAvailable():
          if (_state == SessionState.active) _go(SessionState.doneAvailable);
      }
    }
  }

  /// The model cannot watch this time: no model on the phone or it failed
  /// (LS-5), no strap (CAM-3), or no back camera. The session goes on as a
  /// manual one rather than leaving the child unable to finish, and the
  /// grown-up judges from the Before and After photos.
  void goManual([ManualReason reason = ManualReason.modelUnavailable]) {
    if (mode == CheckMode.manual) return;
    mode = CheckMode.manual;
    manualReason = reason;
    if (_state == SessionState.waitingForMovement || _state == SessionState.active) {
      _go(SessionState.doneAvailable);
      _stopAlarm(reason.key);
    }
  }

  /// The child tapped Done, which only exists in doneAvailable.
  void done() {
    finishedAt = _now();
    _go(SessionState.capturingAfter);
  }

  void afterCaptured() => _go(SessionState.reviewing);

  /// Take the After photo again from the review.
  void retakeAfter() => _go(SessionState.capturingAfter);

  void send() => _go(SessionState.sending);

  void sent() => _go(SessionState.sent);

  void fail(String reason) {
    failure = reason;
    _go(SessionState.failed);
  }

  /// Seconds from Start to Done (or to now while it runs).
  int get sessionSeconds {
    final start = startedAt;
    if (start == null) return 0;
    return (finishedAt ?? _now()).difference(start).inSeconds;
  }
}
