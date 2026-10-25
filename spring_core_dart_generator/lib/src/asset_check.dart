// Build-time check of `@Value('asset:...')` (spring_boot_starter_flutter):
// the asset must exist and be declared under `flutter: assets:` in the
// app's pubspec.yaml, otherwise the app would only fail when it reads it.
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';
import 'package:spring_core_dart_generator/src/bean_model.dart';
import 'package:yaml/yaml.dart';

/// Checks every literal `@Value('asset:<key>')` of the module's beans and
/// `@Configurable` classes, reporting each problem through [collectErrors]:
///
/// ```dart
/// AppAssets(@Value('asset:assets/sounds/tap.mp3') this.tap);
/// // error: assets/sounds/tap.mp3 is not declared in pubspec.yaml; add it
/// // under `flutter: assets:`:
/// //     - assets/sounds/
/// ```
///
/// Not checked: keys with placeholders or SpEL (`asset:${sound.file}`),
/// known only at run time, and other packages' assets (`packages/...`).
/// A directory entry (`- assets/sounds/`) declares the files directly in
/// it, not those of its subdirectories, as in Flutter.
Future<void> checkAssetValues(
  BuildStep buildStep,
  ModuleModel module,
  void Function(void Function() action) collectErrors,
) async {
  final values = [
    for (final bean in module.beans)
      for (final point in bean.dependencies)
        if (_assetKey(point) case final key?) (bean.element, bean.source, key),
    for (final configurable in module.configurables)
      for (final point in [
        for (final property in configurable.properties) property.point,
        for (final method in configurable.methods)
          for (final argument in method.arguments) argument.point,
      ])
        if (_assetKey(point) case final key?)
          (configurable.element, configurable.element.displayName, key),
  ];
  if (values.isEmpty) {
    return;
  }
  final package = buildStep.inputId.package;
  final declared = await _declaredAssets(buildStep, package);
  final existing = <String, bool>{};
  for (final (element, source, key) in values) {
    final exists = existing[key] ??= await _exists(buildStep, package, key);
    collectErrors(() {
      final what = "@Value('asset:$key') in $source";
      if (!exists) {
        throw InvalidGenerationSource(
          '$what: there is no file $key in the package $package.',
          element: element,
        );
      }
      if (!_isDeclared(key, declared)) {
        final directory = p.url.dirname(key);
        final entry = directory == '.' ? key : '$directory/';
        throw InvalidGenerationSource(
          '$what: $key is not declared in pubspec.yaml, so the app would '
          'not contain it. Add it under `flutter: assets:`:\n'
          '\n'
          'flutter:\n'
          '  assets:\n'
          '    - $entry',
          element: element,
        );
      }
    });
  }
}

/// The asset key of a literal `@Value('asset:<key>')` point, or `null`.
String? _assetKey(InjectionPoint point) {
  if (point.kind != PointKind.value) {
    return null;
  }
  final expression = point.expression?.trim();
  if (expression == null ||
      !expression.startsWith('asset:') ||
      expression.contains(r'${') ||
      expression.contains('#{')) {
    return null;
  }
  var key = expression.substring('asset:'.length);
  if (key.startsWith('/')) {
    key = key.substring(1);
  }
  return key.isEmpty || key.startsWith('packages/') ? null : key;
}

/// The entries of `flutter: assets:` in [package]'s pubspec.yaml: plain
/// strings and the `path:` of map entries (`- path: assets/x/`, with
/// `flavors:`).
Future<List<String>> _declaredAssets(
  BuildStep buildStep,
  String package,
) async {
  final pubspec = AssetId(package, 'pubspec.yaml');
  if (!await buildStep.canRead(pubspec)) {
    return const [];
  }
  final Object? yaml;
  try {
    yaml = loadYaml(await buildStep.readAsString(pubspec));
  } on YamlException {
    return const [];
  }
  final assets = yaml is Map && yaml['flutter'] is Map
      ? (yaml['flutter'] as Map)['assets']
      : null;
  if (assets is! List) {
    return const [];
  }
  return [
    for (final entry in assets)
      if (entry is String)
        entry
      else if (entry is Map && entry['path'] is String)
        entry['path'] as String,
  ];
}

/// Whether [key] is one of [declared]: the file itself, or a directory
/// entry (`assets/images/`) holding it directly.
bool _isDeclared(String key, List<String> declared) {
  for (var entry in declared) {
    if (entry.startsWith('./')) {
      entry = entry.substring(2);
    }
    if (entry == key ||
        entry.endsWith('/') &&
            p.url.dirname(key) == entry.substring(0, entry.length - 1)) {
      return true;
    }
  }
  return false;
}

/// Whether the file [key] exists in [package]: through the build (files
/// under `assets/`, `lib/`, ... are build inputs, so adding one reruns the
/// check), else on disk (a directory the build does not see).
Future<bool> _exists(BuildStep buildStep, String package, String key) async {
  try {
    if (await buildStep.canRead(AssetId(package, key))) {
      return true;
    }
  } on Object {
    // Not a valid asset id for the build (e.g. outside the package).
  }
  // The disk check only works for the package the build runs in (the
  // current directory).
  return _isCurrentPackage(package) && File(key).existsSync();
}

bool _isCurrentPackage(String package) {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    return false;
  }
  try {
    final yaml = loadYaml(pubspec.readAsStringSync());
    return yaml is Map && yaml['name'] == package;
  } on Object {
    return false;
  }
}
