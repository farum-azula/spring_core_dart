// Every package a published package imports or exports from lib/ is in its
// `dependencies`: pub.dev refuses the package otherwise ("This package does
// not have X in the `dependencies` section"), and a package that only
// arrives through another dependency passes the tests. The generated code in
// lib/spring_gen/ counts too: it imports spring_core_dart.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../version.dart' as family;

void main() {
  final root = p.dirname(p.dirname(p.dirname(Platform.script.toFilePath())));
  String repo(String path) =>
      Directory(path).existsSync() ? path : p.join(root, path);

  final directive = RegExp(
    r"^\s*(?:import|export)\s+'package:([a-z_0-9]+)/",
    multiLine: true,
  );

  for (final package in family.family) {
    test('$package declares every package its lib/ uses', () {
      final directory = repo(package);
      final pubspec = loadYaml(
        File(p.join(directory, 'pubspec.yaml')).readAsStringSync(),
      ) as YamlMap;
      final dependencies = {
        ...?(pubspec['dependencies'] as YamlMap?)?.keys.cast<String>(),
      };
      final missing = <String, String>{};
      final lib = Directory(p.join(directory, 'lib'));
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) {
          continue;
        }
        for (final match in directive.allMatches(file.readAsStringSync())) {
          final used = match.group(1)!;
          if (used != package && !dependencies.contains(used)) {
            missing.putIfAbsent(
              used,
              () => p.relative(file.path, from: directory),
            );
          }
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            'add to the dependencies of $package/pubspec.yaml '
            '(package: first file that uses it)',
      );
    });
  }
}
