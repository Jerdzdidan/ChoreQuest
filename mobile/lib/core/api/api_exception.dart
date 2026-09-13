/// Every way a call to the ChoreQuest API can fail, as types a screen can
/// switch on.
///
/// Sealed on purpose: code that handles these must handle all of them, so a
/// stopped server can never fall through to a crash screen. Each message is
/// written to be shown to the person holding the phone as it stands.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Nothing came back: no network, the server is not running, or it timed out.
final class ApiUnreachable extends ApiException {
  const ApiUnreachable()
      : super(
          "Can't reach ChoreQuest. Check that this phone is online and the "
          'server is running.',
        );
}

/// The token is missing, expired, or was revoked.
final class ApiUnauthorised extends ApiException {
  const ApiUnauthorised([super.message = 'Please sign in again.']);
}

/// Signed in, but not allowed here: a child's token on a parent's screen.
final class ApiForbidden extends ApiException {
  const ApiForbidden([super.message = "This isn't available on this account."]);
}

/// The server understood the request and turned it down: a validation error,
/// a wrong PIN, an unknown household code.
final class ApiRejected extends ApiException {
  const ApiRejected(
    super.message, {
    this.statusCode,
    this.fieldErrors = const {},
  });

  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  String? errorFor(String field) {
    final errors = fieldErrors[field];
    return errors == null || errors.isEmpty ? null : errors.first;
  }
}

/// Too many attempts: the per-minute throttle, or a child profile locked after
/// repeated wrong PINs.
final class ApiLocked extends ApiException {
  const ApiLocked(super.message, {this.lockedUntil});

  final DateTime? lockedUntil;
}

/// The server failed while handling a valid request.
final class ApiServerError extends ApiException {
  const ApiServerError([
    super.message =
        'The ChoreQuest server ran into a problem. Try again in a moment.',
  ]);
}
