@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

// FetchHttpTransport runs on the web: test/js/fetch_main.dart is compiled
// to JavaScript and run with node (whose fetch supports data: URLs). This
// also proves the main library compiles for the web.
void main() {
  test('FetchHttpTransport under node', () async {
    final node = await _hasNode();
    if (!node) {
      markTestSkipped('node is not on the PATH');
      return;
    }
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:spring_web_dart/'),
    );
    final package = Directory.fromUri(lib!).parent.path;
    final temp = Directory.systemTemp.createTempSync('spring_web_fetch_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final output = '${temp.path}/fetch_main.js';
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'js',
      '-o',
      output,
      'test/js/fetch_main.dart',
    ], workingDirectory: package);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
    final run = await Process.run('node', [
      '-e',
      'globalThis.self = globalThis; require(${jsonEncode(output)})',
    ]);
    expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
    final line = (run.stdout as String)
        .split('\n')
        .firstWhere((l) => l.startsWith('RESULT '));
    final result = jsonDecode(line.substring(7)) as Map<String, Object?>;
    expect(result, {
      'platform': true,
      'status': 200,
      'body': {'isbn': '1'},
      'contentType': 'application/json',
      'refused': 'error',
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<bool> _hasNode() async {
  try {
    return (await Process.run('node', ['--version'])).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
