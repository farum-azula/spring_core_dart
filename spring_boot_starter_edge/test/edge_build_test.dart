// What the build refuses before it compiles anything, and what every
// WebAssembly loader gives the module.
import 'dart:io';

import 'package:spring_boot_starter_edge/build.dart';
import 'package:test/test.dart';

void main() {
  // A dart that says it is [version] and fails to compile: what the build
  // does before it compiles shows, without compiling anything.
  String fakeDart(String version) {
    final directory = Directory.systemTemp.createTempSync('spring_dart_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/dart')
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'if [ "\$1" = "--version" ]; then\n'
        '  echo "Dart SDK version: $version (stable)"; exit 0\n'
        'fi\n'
        'echo "not compiled" >&2; exit 3\n',
      );
    Process.runSync('chmod', ['+x', file.path]);
    return file.path;
  }

  EdgeBuild build(EdgePlatform platform, String dart, Directory output) =>
      EdgeBuild(
        platform: platform,
        application: Directory.current,
        output: output.path,
        target: EdgeTarget.wasm,
        dart: dart,
      );

  Directory output() {
    final directory = Directory.systemTemp.createTempSync('spring_edge_');
    addTearDown(() => directory.deleteSync(recursive: true));
    return directory;
  }

  test(
    'WebAssembly for Supabase compiled by Dart 3.14 or later is refused, '
    'saying that Dart 3.13 works until Supabase updates its runtime',
    () async {
      for (final version in ['3.14.0', '3.15.2', '4.0.0']) {
        final out = output();
        await expectLater(
          build(EdgePlatform.supabase, fakeDart(version), out).run,
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('works only when Dart 3.13 compiles it'),
                contains('until Supabase updates its Edge Runtime'),
                contains('exnref'),
                contains("This build's Dart is $version"),
                contains('--dart'),
                contains('--target js'),
              ),
            ),
          ),
          reason: version,
        );
        expect(out.listSync(), isEmpty, reason: 'nothing written');
      }
    },
    testOn: 'posix',
  );

  test('compiled by Dart 3.13 it is built as before', () async {
    for (final version in ['3.13.0', '3.13.7', '3.12.4']) {
      // The fake does not compile: the build got past the check.
      await expectLater(
        build(EdgePlatform.supabase, fakeDart(version), output()).run,
        throwsA(isA<ProcessException>()),
        reason: version,
      );
    }
  }, testOn: 'posix');

  test('the other platforms take WebAssembly of every Dart', () async {
    for (final platform in EdgePlatform.values) {
      expect(
        platform.newestWasmDart,
        platform == EdgePlatform.supabase ? '3.13.7' : isNull,
        reason: platform.name,
      );
    }
    await expectLater(
      build(EdgePlatform.cloudflare, fakeDart('3.14.0'), output()).run,
      throwsA(isA<ProcessException>()),
    );
  }, testOn: 'posix');

  test('every WebAssembly loader gives the module stand-ins for the '
      'JavaScript string builtins, bound to its exports', () {
    for (final runtime in ['node', 'deno', 'cloudflare']) {
      final loader = wasmLoader(runtime);
      expect(
        loader,
        allOf(
          contains('const jsStrings = {'),
          contains('"wasm:js-string": jsStrings'),
          contains('appExports = instance.instantiatedModule.exports;'),
          contains(r'appExports.$wasmI16ArrayGet'),
          contains(r'appExports.$wasmI16ArraySet'),
        ),
        reason: runtime,
      );
      for (final name in [
        'cast', 'test', 'length', 'charCodeAt', 'codePointAt', 'concat', //
        'substring', 'equals', 'compare', 'fromCharCode', 'fromCodePoint',
        'fromCharCodeArray', 'intoCharCodeArray',
      ]) {
        expect(loader, contains('  $name: '), reason: '$runtime $name');
      }
    }
  });
}
