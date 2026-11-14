import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;
import 'package:spring_boot_dart/spring_boot_dart.dart'
    show
        EnumerablePropertySource,
        PropertiesPropertySourceLoader,
        YamlPropertySourceLoader;

final RegExp _key = RegExp(
  r'^spring\.flutter\.scene\.materials\.([^.\[]+)\.source$',
);

/// A material the app's configuration names: [name] with [source], set
/// in the file [file] (its path from the app's root).
final class DeclaredSceneMaterial {
  /// Material [name] of [source], declared in [file].
  const DeclaredSceneMaterial(this.name, this.source, this.file);

  /// Its name, `spring.flutter.scene.materials.<name>`.
  final String name;

  /// Its `.fmat` file, as written.
  final String source;

  /// The configuration file that names it.
  final String file;
}

/// The materials the configuration files of the app at [app] name
/// (`lib/resources/application*.yml`, `.yaml`, `.properties`, profiles
/// too), each file a dependency of the hook in [buildOutput] so a change
/// runs it again. A source written with a placeholder (`${...}`) is left
/// out: it is known only when the app runs.
List<DeclaredSceneMaterial> declaredSceneMaterials(
  String app, {
  BuildOutputBuilder? buildOutput,
}) {
  final resources = Directory(p.join(app, 'lib', 'resources'));
  if (!resources.existsSync()) {
    return const [];
  }
  buildOutput?.dependencies.add(resources.uri);
  final files =
      resources
          .listSync()
          .whereType<File>()
          .where((file) => p.basename(file.path).startsWith('application'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final declared = <DeclaredSceneMaterial>[];
  for (final file in files) {
    final name = p.basename(file.path);
    final extension = p.extension(name).replaceFirst('.', '');
    final sources = switch (extension) {
      'yml' || 'yaml' => const YamlPropertySourceLoader().load(
        name,
        file.readAsStringSync(),
      ),
      'properties' => const PropertiesPropertySourceLoader().load(
        name,
        file.readAsStringSync(),
      ),
      _ => null,
    };
    if (sources == null) {
      continue;
    }
    buildOutput?.dependencies.add(file.uri);
    final relative = p.posix.joinAll(p.split(p.relative(file.path, from: app)));
    for (final source
        in sources.whereType<EnumerablePropertySource<Object>>()) {
      for (final key in source.propertyNames) {
        final match = _key.firstMatch(key);
        final value = source.getProperty(key);
        if (match == null || value is! String || value.contains(r'${')) {
          continue;
        }
        declared.add(DeclaredSceneMaterial(match[1]!, value, relative));
      }
    }
  }
  return declared;
}

/// Fails the build when a material of the configuration ([declared]) is
/// not among the `.fmat` files the hook compiled ([compiled], their paths
/// from the app's root), naming the key, the file it is set in and what
/// there is.
void checkSceneMaterials(
  List<DeclaredSceneMaterial> declared,
  Iterable<String> compiled, {
  required String sources,
}) {
  final known = compiled.toSet();
  final wrong = [
    for (final material in declared)
      if (!known.contains(material.source)) material,
  ];
  if (wrong.isEmpty) {
    return;
  }
  final lines = [
    for (final material in wrong)
      '- spring.flutter.scene.materials.${material.name}.source '
          '(${material.file}) is ${material.source}'
          '${material.source.startsWith('asset:') ? ': write the path without asset:' : ''}',
  ];
  throw StateError(
    'Materials of the configuration that the build did not compile:\n'
    '${lines.join('\n')}\n'
    '${known.isEmpty ? 'There is no .fmat file under $sources.' : 'The .fmat files under $sources: ${(known.toList()..sort()).join(', ')}.'}',
  );
}
