/// Build-time configuration.
///
/// The API address is injected with --dart-define, so the same code runs
/// against an emulator, a phone on the same Wi-Fi, and the hosted API used in
/// the field test, without anyone editing source:
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
///
/// Inside the Android emulator 10.0.2.2 is the host machine. From a real phone,
/// use the PC's address on the local network instead.
abstract final class AppConfig {
  static String get apiBaseUrl {
    const raw = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:8000/api',
    );
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  static const connectTimeout = Duration(seconds: 8);
  static const receiveTimeout = Duration(seconds: 20);
}
