import 'dart:math';

/// A random version 4 UUID, created on the phone before an upload is tried.
///
/// The server stores it with the submission and answers a repeat of the same
/// token with the original submission, so a retried upload lands once. Built
/// by hand rather than from a package: sixteen secure random bytes with two
/// fields fixed is the whole of the format.
String newClientToken([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));

  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant

  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
  return '${hex.sublist(0, 4).join()}-'
      '${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-'
      '${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10, 16).join()}';
}
