// Scenario "cpu": the same CPU-bound work in the request's isolate and
// through the IsolateTaskExecutor, and an endpoint that only waits, for
// the overload checks.
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
class CpuController {
  CpuController(this._isolate, this._tasks);

  final IsolateInfo _isolate;
  final IsolateTaskExecutor _tasks;

  /// `GET /cpu/inline?rounds=2000`: SHA-256 over 4 KB, `rounds` times, in
  /// the isolate that answers. Nothing else is answered by that isolate
  /// meanwhile.
  @GetMapping('/cpu/inline')
  CpuWork inline({@RequestParam('rounds') int rounds = 1000}) {
    final watch = Stopwatch()..start();
    final digest = hashRounds(_checked(rounds));
    return CpuWork(digest, rounds, watch.elapsedMicroseconds, _isolate.name);
  }

  /// `GET /cpu/task?rounds=2000`: the same work in an isolate of the
  /// task executor (`task-1`); the request's isolate goes on answering.
  @GetMapping('/cpu/task')
  Future<CpuWork> task({@RequestParam('rounds') int rounds = 1000}) async {
    final watch = Stopwatch()..start();
    final digest = await _tasks.submitWith(hashRounds, _checked(rounds));
    return CpuWork(digest, rounds, watch.elapsedMicroseconds, _isolate.name);
  }

  /// `GET /slow?ms=50`: answers after that long without using the
  /// processor, so many requests are in flight at once.
  @GetMapping('/slow')
  Future<String> slow({@RequestParam('ms') int milliseconds = 50}) async {
    if (milliseconds < 0 || milliseconds > 60000) {
      throw ResponseStatusException(HttpStatus.badRequest, 'ms: 0 to 60000');
    }
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
    return 'Waited $milliseconds ms';
  }

  static int _checked(int rounds) => rounds >= 1 && rounds <= 10000000
      ? rounds
      : throw ResponseStatusException(
          HttpStatus.badRequest,
          'rounds: 1 to 10000000',
        );

  /// The work: the digest of a block of 4 KB, hashed again with its own
  /// digest [rounds] times. Deterministic, and static so that it crosses
  /// to another isolate with nothing but its argument.
  static String hashRounds(int rounds) {
    final block = Uint8List(4096);
    for (var i = 0; i < block.length; i++) {
      block[i] = i & 0xff;
    }
    var digest = sha256.convert(block);
    for (var round = 1; round < rounds; round++) {
      block.setRange(0, digest.bytes.length, digest.bytes);
      digest = sha256.convert(block);
    }
    return digest.toString();
  }
}

/// The answer of the CPU endpoints.
class CpuWork {
  const CpuWork(this.digest, this.rounds, this.micros, this.isolate);

  /// The last digest, in hexadecimal: the same for the same [rounds].
  final String digest;
  final int rounds;

  /// How long the request's isolate waited for the work, in microseconds.
  final int micros;

  /// The isolate that answered.
  final String isolate;
}
