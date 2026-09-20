import 'package:flutter/services.dart';

/// Answered by MainActivity with Android's own timezone setting.
const _channel = MethodChannel('com.chorequest/timezone');

/// The phone's own timezone as an IANA name, such as `Asia/Manila`, or null
/// if the platform cannot say. Reading it needs no permission: it is the
/// setting the phone's clock already uses.
Future<String?> readDeviceTimezone() async {
  try {
    final identifier = (await _channel.invokeMethod<String>('localTimezone'))?.trim();
    return identifier == null || identifier.isEmpty ? null : identifier;
  } catch (_) {
    // No handler (a test, or a platform without one): send nothing.
    return null;
  }
}
