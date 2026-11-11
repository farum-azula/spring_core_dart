import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';

/// Loads the sources of the real packages (the isolate's) into [readerWriter],
/// writes the sources of [sources] that are not in [rootPackage] over them,
/// and returns the sources of [rootPackage] only: the ones to build.
///
/// A package that has a source in the `testBuilder` call is built too, and
/// build_runner refuses to build over a generated file that is already there
/// (the real starters keep the binding of their typed properties in
/// `lib/spring_gen/`). Written to the reader/writer, the fake sources of a
/// starter replace the real ones for reading only.
Future<Map<String, Object>> loadRealSources(
  TestReaderWriter readerWriter,
  Map<String, Object> sources, {
  String rootPackage = 'pkg',
}) async {
  await readerWriter.testing.loadIsolateSources();
  final own = <String, Object>{};
  sources.forEach((key, contents) {
    final id = AssetId.parse(key);
    if (id.package == rootPackage) {
      own[key] = contents;
    } else if (contents is String) {
      readerWriter.testing.writeString(id, contents);
    } else if (contents is List<int>) {
      readerWriter.testing.writeBytes(id, contents);
    }
  });
  return own;
}

/// Writes the `pubspec.yaml` of every real package (the isolate's) into
/// [readerWriter], as a build reads them: the generator then knows which
/// packages the application reaches, instead of taking every package of
/// the package config (what it does when a pubspec cannot be read).
///
/// Call it before [loadRealSources], whose sources may replace one.
Future<void> loadRealPubspecs(TestReaderWriter readerWriter) async {
  final config = await loadPackageConfigUri((await Isolate.packageConfig)!);
  for (final package in config.packages) {
    final file = File.fromUri(package.root.resolve('pubspec.yaml'));
    if (file.existsSync()) {
      readerWriter.testing.writeString(
        AssetId(package.name, 'pubspec.yaml'),
        file.readAsStringSync(),
      );
    }
  }
}
