import '../../core/api/api_client.dart';

/// A forgotten password, reset with a 6-digit code sent by email (PA-3).
/// The server answers the same whether or not the email has an account.
class PasswordResetApi {
  const PasswordResetApi(this._api);

  final ApiClient _api;

  /// Asks for a code. Returns the server's answer to show.
  Future<String> sendCode(String email) async =>
      (await _api.post('/password/forgot', body: {'email': email}))['message'] as String? ??
      'If that email has an account, we sent a code.';

  /// Checks the code before a new password is chosen. A wrong one is an
  /// ApiRejected with the reason under `code`.
  Future<void> checkCode(String email, String code) =>
      _api.post('/password/verify-code', body: {'email': email, 'code': code});

  /// Sets the new password with the code. Returns the server's answer.
  Future<String> reset(String email, String code, String password) async =>
      (await _api.post('/password/reset', body: {
        'email': email,
        'code': code,
        'password': password,
        'password_confirmation': password,
      }))['message'] as String? ??
      'Your password is changed. Sign in with your new password.';
}

/// "jdoe@gmail.com" as "j•••@gmail.com": enough to recognise, not to read
/// over a shoulder.
String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at < 1) return email;
  return '${email[0]}•••${email.substring(at)}';
}
