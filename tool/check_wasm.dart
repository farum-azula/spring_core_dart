// Every package an app can run in a browser compiles to WebAssembly
// (docs/dependencies.md, "WebAssembly"): for each package of
// [wasmPackages], writes a program importing every public library of the
// package (`lib/*.dart`) and compiles it with `dart compile wasm`; an
// import Wasm cannot have (`dart:html`, `dart:js`, `dart:js_util`,
// `package:js`, `dart:ffi` outside a conditional import, ...) fails it.
//
//   dart run tool/check_wasm.dart                  # the Dart packages
//   dart run tool/check_wasm.dart spring_core_dart # some of them
//   dart run tool/check_wasm.dart --flutter        # the Flutter starters
//
// With --flutter (the Flutter SDK: CI runs it in the `flutter` job) it
// builds, for each app of [flutterApps], a program importing every public
// library of its Flutter starters with `flutter build web --wasm`.
//
// `dart:io` compiles to Wasm (its calls throw in a browser): code that
// needs it sits behind a conditional import or a platform check, which
// the docs' rule asks for and the tests of each package run.
import 'dart:io';

/// The packages of the repository an app can run in a browser.
const wasmPackages = [
  'spring_core_dart',
  'spring_boot_dart',
  'spring_boot_starter_logging',
  'spring_boot_starter_scheduling',
  'spring_boot_starter_cache',
  'spring_boot_starter_feign',
  'spring_boot_starter_websocket',
  'spring_boot_starter_data',
  'spring_security_core',
  'spring_search_dart',
  // The server's: their modules are left out of a browser build
  // (`ModulePlatform.native`), but an application that shares its code
  // between a server and a Flutter web app lists them, and its generated
  // file imports their auto-configuration libraries.
  'spring_boot_starter_web',
  'spring_boot_actuator',
  'spring_boot_starter_actuator',
  'spring_boot_starter_oauth2_client',
  'spring_boot_starter_security',
];

/// The apps the Flutter starters are built in, with the starters each
/// imports.
const flutterApps = {
  'example/flutter_guide': [
    'spring_boot_starter_flutter',
    'spring_boot_starter_flutter_security',
  ],
  'example/seo_site': [
    'spring_boot_starter_flutter',
    'spring_boot_starter_flutter_navigation',
  ],
};

Future<void> main(List<String> args) async {
  final flutter = args.contains('--flutter');
  final chosen = [
    for (final arg in args)
      if (!arg.startsWith('--')) arg,
  ];
  final failures = <String>[];
  if (flutter) {
    for (final MapEntry(key: app, value: packages) in flutterApps.entries) {
      if (!await _flutter(app, packages)) {
        failures.add(app);
      }
    }
  } else {
    for (final package in chosen.isEmpty ? wasmPackages : chosen) {
      if (!await _dart(package)) {
        failures.add(package);
      }
    }
  }
  if (failures.isNotEmpty) {
    stderr.writeln(
      'Not compiled to WebAssembly: ${failures.join(', ')} '
      '(docs/dependencies.md, "WebAssembly").',
    );
    exit(1);
  }
}

// `import 'package:p/x.dart' as _x;` for every public library of [package].
String _imports(String package) {
  final libraries =
      Directory('$package/lib')
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.endsWith('.dart'))
          .toList()
        ..sort();
  return [
    for (final (i, name) in libraries.indexed)
      "import 'package:$package/$name' as _${package}_$i;",
  ].join('\n');
}

Future<bool> _dart(String package) async {
  final dir = Directory('.dart_tool/wasm_check')..createSync(recursive: true);
  final entry = File('${dir.path}/$package.dart')
    ..writeAsStringSync(
      '// ignore_for_file: unused_import\n'
      '${_imports(package)}\n\nvoid main() {}\n',
    );
  final result = await Process.run('dart', [
    'compile',
    'wasm',
    entry.path,
    '-o',
    '${dir.path}/$package.wasm',
  ]);
  return _report(package, result);
}

Future<bool> _flutter(String app, List<String> packages) async {
  final dir = Directory('$app/.dart_tool/wasm_check')
    ..createSync(recursive: true);
  File('${dir.path}/main.dart').writeAsStringSync(
    '// ignore_for_file: unused_import\n'
    '${[for (final package in packages) _imports(package)].join('\n')}\n\n'
    'void main() {}\n',
  );
  final result = await Process.run('flutter', [
    'build',
    'web',
    '--wasm',
    '--no-pub',
    '-t',
    '.dart_tool/wasm_check/main.dart',
    '-o',
    '.dart_tool/wasm_check/build',
  ], workingDirectory: app);
  return _report('$app (${packages.join(', ')})', result);
}

bool _report(String what, ProcessResult result) {
  if (result.exitCode == 0) {
    stdout.writeln('✓ $what');
    return true;
  }
  stdout.writeln('✗ $what\n${result.stdout}${result.stderr}');
  return false;
}
