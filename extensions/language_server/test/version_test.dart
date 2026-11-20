@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_dart/src/version.dart';
import 'package:test/test.dart';

/// `dart_spring_lsp --version`, which the Zed extension compares with its own
/// version before it starts a server found on the PATH.
void main() {
  late String package;
  late String pubspecVersion;

  setUpAll(() async {
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:dart_spring_language_server/'),
    );
    package = Directory.fromUri(lib!).parent.path;
    final pubspec = File('$package/pubspec.yaml').readAsStringSync();
    pubspecVersion = RegExp(
      r'^version: (\S+)$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
  });

  test('the version it prints is the one of its pubspec.yaml', () {
    expect(springBootVersion, pubspecVersion);
  });

  test('--version prints it and exits', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      '$package/bin/dart_spring_lsp.dart',
      '--version',
    ], workingDirectory: package);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout, 'dart_spring_lsp $pubspecVersion\n');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
