// Scenario "text": the least a request can cost (routing, a String
// written as text/plain), and the bench's own status.
import 'dart:io';

import 'package:load_bench/src/bench_files.dart';
import 'package:load_bench/src/security_config.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()
class TextController {
  TextController(this._files, this._token);

  final BenchFiles _files;
  final BenchToken _token;

  /// `GET /text`.
  @GetMapping('/text')
  String text() => 'Hello, load!';

  /// `GET /bench/info`: whether the files are ready, the process and its
  /// memory, the bearer token of `/secure/**`. The load tool waits for
  /// `ready` and reads the rest.
  @GetMapping('/bench/info')
  BenchInfo info() => BenchInfo(
    ready: _files.ready,
    pid: pid,
    rss: ProcessInfo.currentRss,
    maxRss: ProcessInfo.maxRss,
    processors: Platform.numberOfProcessors,
    files: _files.sizes,
    token: _token.value,
  );
}

/// The answer of `GET /bench/info`.
class BenchInfo {
  const BenchInfo({
    required this.ready,
    required this.pid,
    required this.rss,
    required this.maxRss,
    required this.processors,
    required this.files,
    required this.token,
  });

  /// Whether the files to download exist.
  final bool ready;

  /// The server's process: the tool samples its memory with `ps`.
  final int pid;

  /// The resident memory of the process now and at its highest, in bytes
  /// (every isolate of the server together).
  final int rss;
  final int maxRss;

  /// The processor cores the server sees.
  final int processors;

  /// The size of each file of `GET /files/{name}`, in bytes.
  final Map<String, int> files;

  /// The token for `Authorization: Bearer` on `/secure/**`.
  final String token;
}
