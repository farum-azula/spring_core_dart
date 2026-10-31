import 'dart:async';
import 'dart:collection';

import 'package:spring_security_core/src/authentication/concurrency_stub.dart'
    if (dart.library.io) 'package:spring_security_core/src/authentication/concurrency_io.dart';

/// Too many password checks are running and waiting: this one was not
/// started.
///
/// Thrown at once, without spending CPU or memory, when the
/// [PasswordCheckLimiter]'s queue is full. The security starter answers
/// it with `503 Service Unavailable` and `Retry-After`, never as a failed
/// login: the credentials were not checked.
///
/// Spring (Java): none (a servlet container's full thread pool queues or
/// refuses the connection instead).
class PasswordChecksBusyException implements Exception {
  /// A refusal when [maxConcurrent] checks run and [maxQueued] wait.
  PasswordChecksBusyException(this.maxConcurrent, this.maxQueued);

  /// The checks that may run at once.
  final int maxConcurrent;

  /// The checks that may wait.
  final int maxQueued;

  @override
  String toString() =>
      'PasswordChecksBusyException: $maxConcurrent password checks running '
      'and $maxQueued waiting';
}

/// Bounds the password checks (hashing) of the `DaoAuthenticationProvider`:
/// at most [maxConcurrent] run at once, at most [maxQueued] wait, and
/// another one fails at once with a [PasswordChecksBusyException].
///
/// A password hash takes tens of milliseconds of CPU and (Argon2) megabytes
/// of memory, on an isolate of its own. Without a bound, a flood of logins
/// with wrong passwords (no account needed) takes every core of the
/// machine and more memory with each request; with it, the cost of a flood
/// is [maxConcurrent] cores, and the rest of the application keeps its
/// speed. By default [maxConcurrent] is half the processors (at least
/// one), so a flood leaves the other half to the rest of the application
/// and to the machine's other services, and [maxQueued] is eight times
/// that.
///
/// Spring (Java): none; the container's thread pool bounds the work there.
final class PasswordCheckLimiter {
  /// A limiter running [maxConcurrent] checks at once with [maxQueued]
  /// waiting (both at least 1 and 0).
  PasswordCheckLimiter({int? maxConcurrent, int? maxQueued})
    : maxConcurrent = maxConcurrent ?? defaultMaxConcurrent,
      maxQueued = maxQueued ?? (maxConcurrent ?? defaultMaxConcurrent) * 8 {
    if (this.maxConcurrent < 1 || this.maxQueued < 0) {
      throw ArgumentError(
        'maxConcurrent must be at least 1 and maxQueued at least 0',
      );
    }
  }

  /// Half the processors, at least one.
  static int get defaultMaxConcurrent =>
      processorCount ~/ 2 < 1 ? 1 : processorCount ~/ 2;

  /// The limiter of the providers that are given none.
  static PasswordCheckLimiter shared = PasswordCheckLimiter();

  /// The checks that may run at once.
  final int maxConcurrent;

  /// The checks that may wait for a free place.
  final int maxQueued;

  int _running = 0;
  final _waiting = Queue<Completer<void>>();

  /// The checks running now.
  int get running => _running;

  /// The checks waiting now.
  int get waiting => _waiting.length;

  /// Runs [check] when a place is free; throws a
  /// [PasswordChecksBusyException] at once when [maxQueued] already wait.
  Future<T> run<T>(Future<T> Function() check) async {
    if (_running >= maxConcurrent) {
      if (_waiting.length >= maxQueued) {
        throw PasswordChecksBusyException(maxConcurrent, maxQueued);
      }
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future; // the place is handed over: _running stays
    } else {
      _running++;
    }
    try {
      return await check();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}
