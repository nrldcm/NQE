// Small shared helpers.
import 'dart:math';

final _rand = Random();

/// Reasonably-unique id without extra dependencies (timestamp + randomness).
String uid() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = _rand.nextInt(0x7fffffff).toRadixString(36);
  return '$t$r';
}

String nowIso() => DateTime.now().toIso8601String();
