import 'dart:math';

final _random = Random.secure();

/// A random 32-character id, e.g. "7f3a9c2e41b84d0e9a1b2c3d4e5f6071".
///
/// 128 random bits: two phones will not produce the same id in practice,
/// so ids can be created on the phone without asking the server first.
/// That's what makes retries (and later, offline sales) safe.
String randomId() =>
    List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
