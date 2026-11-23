// An application built by the generator, written out and run in its own
// process: what it prints after `RESULT ` is the result.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

/// Builds [sources] (paths in package `pkg`) with every proxy mode on, runs
/// `bin/main.dart` with [arguments], and returns the JSON it printed after
/// `RESULT `. With [sqlite] the process finds the workspace's SQLite library,
/// which `dart run` would otherwise have linked for it.
Future<Object?> runGeneratedApp(
  Map<String, String> sources, {
  List<String> arguments = const [],
  bool sqlite = false,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(generations: packageGenerations),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  final directory = await Directory.systemTemp.createTemp('spring_app_');
  addTearDown(() => directory.delete(recursive: true));
  final files = {
    ...sources,
    for (final output in result.outputs)
      output.path: readerWriter.testing.readString(output),
  };
  for (final MapEntry(:key, :value) in files.entries) {
    final file = File('${directory.path}/$key');
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
  }
  final workspace = await loadPackageConfigUri((await Isolate.packageConfig)!);
  await savePackageConfig(
    PackageConfig([
      ...workspace.packages,
      Package(
        'pkg',
        directory.uri,
        packageUriRoot: directory.uri.resolve('lib/'),
      ),
    ]),
    directory,
  );
  if (sqlite) {
    await _linkSqlite(workspace, directory);
  }
  final process = await Process.run(Platform.resolvedExecutable, [
    '--packages=${directory.path}/.dart_tool/package_config.json',
    '${directory.path}/bin/main.dart',
    ...arguments,
  ]);
  final output = '${process.stdout}';
  final line = LineSplitter.split(
    output,
  ).where((line) => line.startsWith('RESULT ')).firstOrNull;
  expect(line, isNotNull, reason: '$output\n${process.stderr}');
  return jsonDecode(line!.substring('RESULT '.length));
}

// The native assets mapping the VM reads beside the package config.
Future<void> _linkSqlite(PackageConfig workspace, Directory directory) async {
  final generator = workspace.packages.firstWhere(
    (package) => package.name == 'spring_core_dart_generator',
  );
  final tool = Directory.fromUri(generator.root.resolve('../.dart_tool/'));
  final library = await tool
      .list(recursive: true, followLinks: false)
      .where(
        (entity) =>
            entity is File &&
            RegExp(r'[/\\](lib)?sqlite3\.(dylib|so|dll)$')
                .hasMatch(entity.path),
      )
      .first;
  await File('${directory.path}/.dart_tool/native_assets.yaml').writeAsString(
    jsonEncode({
      'format-version': [1, 0, 0],
      'native-assets': {
        '${Abi.current()}': {
          'package:sqlite3/src/ffi/libsqlite3.g.dart': [
            'absolute',
            library.absolute.path,
          ],
        },
      },
    }),
  );
}
