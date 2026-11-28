// What a large upload costs: a 100 MB file sent through a RestClient as a
// multipart part to a local dart:io HttpServer in another isolate (which
// counts the bytes and keeps none), the way it had to be sent before
// streamed bodies (the file read into memory, `MultipartBodyPart.file`,
// the body encoded whole) against the streamed way
// (`MultipartBodyPart.fromPath`, read from the disk while it is sent).
// Each way runs in a process of its own, so that its peak RSS is its own.
// Not part of the tests; run with
//   dart run benchmark/upload_benchmark.dart
//   dart compile exe benchmark/upload_benchmark.dart -o /tmp/up && /tmp/up
//
// November 2026, Apple M5, AOT, loopback, medians of 3 runs of each way
// (four series); the peak RSS of the process (the client and the server
// isolate), what it grew by from its start, and the time of the upload,
// from reading the file to the answer:
//   buffered:  peak RSS 354-365 MB (342-352 MB above the start), 43-48 ms
//   streamed:  peak RSS  28-34 MB  ( 16-22 MB above the start), 54-61 ms
// The buffered way holds the file more than three times over at its peak
// (its bytes, the encoded body, the copies of the garbage collector's
// lag); the streamed one 64 KB chunks of it (File.openRead), whatever its
// size. Streamed costs about 10 ms more per 100 MB on loopback (1.8 GB/s
// against 2.2 GB/s: 1 600 reads of 64 KB instead of one), far above what
// a network carries.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:spring_web_dart/io.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const int _size = 100 * 1024 * 1024;
const _runs = 3;
const List<String> _ways = ['buffered', 'streamed'];

Future<void> main(List<String> args) async {
  if (args.length == 2) {
    await _measure(args[0], args[1]);
    return;
  }
  final directory = Directory.systemTemp.createTempSync('spring_upload_');
  try {
    final file = File('${directory.path}/upload.bin');
    final random = Random(1);
    final sink = file.openWrite();
    final chunk = List<int>.generate(1024 * 1024, (_) => random.nextInt(256));
    for (var written = 0; written < _size; written += chunk.length) {
      sink.add(chunk);
    }
    await sink.close();
    // An AOT executable runs itself; `dart run` runs this script again.
    final self = Platform.script.toFilePath().endsWith('.dart')
        ? [Platform.script.toFilePath()]
        : <String>[];
    for (final way in _ways) {
      final rss = <double>[];
      final above = <double>[];
      final times = <int>[];
      for (var run = 0; run < _runs; run++) {
        final result = await Process.run(Platform.resolvedExecutable, [
          ...self,
          way,
          file.path,
        ]);
        if (result.exitCode != 0) {
          stderr.write('${result.stdout}${result.stderr}');
          exit(1);
        }
        final [start, peak, millis] = (result.stdout as String)
            .trim()
            .split(' ')
            .map(int.parse)
            .toList();
        rss.add(peak / (1024 * 1024));
        above.add((peak - start) / (1024 * 1024));
        times.add(millis);
      }
      String median(List<num> values, [int digits = 1]) =>
          (values.toList()..sort())[_runs ~/ 2]
              .toStringAsFixed(digits)
              .padLeft(6);
      stdout.writeln(
        '${'$way:'.padRight(10)} peak RSS ${median(rss)} MB '
        '(${median(above)} MB above the start), ${median(times, 0)} ms',
      );
    }
  } finally {
    directory.deleteSync(recursive: true);
  }
}

// One upload of [path] the [way] says; prints the peak RSS and the time.
Future<void> _measure(String way, String path) async {
  final start = ProcessInfo.currentRss;
  final ready = ReceivePort();
  await Isolate.spawn(_server, ready.sendPort);
  final port = await ready.first as int;
  final transport = IoHttpTransport();
  final rest = RestClient.builder()
      .baseUrl('http://127.0.0.1:$port')
      .transport(transport)
      .build();
  final clock = Stopwatch()..start();
  final part = switch (way) {
    'buffered' => MultipartBodyPart.file(
      'file',
      await File(path).readAsBytes(),
      filename: 'upload.bin',
    ),
    _ => MultipartBodyPart.fromPath('file', path),
  };
  final received = await rest
      .post()
      .uri('/upload')
      .body(MultipartBody([part]))
      .retrieve()
      .body<String>();
  clock.stop();
  if (int.parse(received) < _size) {
    throw StateError('the server got $received bytes');
  }
  transport.close();
  stdout.writeln(
    '$start ${ProcessInfo.maxRss} ${clock.elapsedMilliseconds}',
  );
  exit(0);
}

// The server: counts the bytes of each request, keeps none.
Future<void> _server(SendPort ready) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  ready.send(server.port);
  await for (final request in server) {
    var size = 0;
    await for (final chunk in request) {
      size += chunk.length;
    }
    request.response.write('$size');
    await request.response.close();
  }
}
