import 'dart:io';

import 'package:dart_spring_language_server/src/diagnostics/problem.dart';
import 'package:dart_spring_language_server/src/flutter_assets.dart';
import 'package:dart_spring_language_server/src/handled.dart';
import 'package:dart_spring_language_server/src/project_model.dart';
import 'package:dart_spring_language_server/src/strings/string_context.dart';
import 'package:dart_spring_language_server/src/strings/string_role.dart';
import 'package:dart_spring_language_server/src/symbols/target.dart';

final _location = RegExp(r'^(?:optional:)?(resources\*?|file|asset):(.+)$');

/// A resource location, wherever it is written (`@PropertySource`,
/// `@Value`, `getResource(...)`): `resources:legacy.properties` goes to the
/// file in `lib/resources/` of the package (`test/resources/` first for a
/// test file, like the test classpath), `file:` paths are relative to the
/// package directory (where the app is run), `asset:` keys
/// (spring_boot_starter_flutter) to the asset.
///
/// An `asset:` location of `@Value` is checked as the generator checks it:
/// the file must exist and be declared under `flutter: assets:` in
/// `pubspec.yaml`. Keys with placeholders or SpEL and other packages'
/// assets (`packages/...`) are not followed.
final class ResourceRole extends StringRole {
  /// The role, over [model].
  const ResourceRole(this.model);

  /// What the workspace knows.
  final ProjectModel model;

  @override
  Handled<Target>? target(StringContext string, int offset) {
    final value = string.value.trim();
    final match = _location.firstMatch(value);
    if (match == null) {
      return null;
    }
    final location = match.group(2)!;
    if (location.endsWith('/')) {
      return null; // a directory, like `resources:/config/`
    }
    final searched = _candidates(string.path, match.group(1)!, location);
    if (searched == null) {
      return null;
    }
    return Handled(
      ResourceTarget(value, [
        for (final candidate in searched)
          if (File(candidate).existsSync()) candidate,
      ], searched),
    );
  }

  // The files [location] of the [scheme] may be, read from [path]; `null`
  // for another package's asset.
  List<String>? _candidates(String path, String scheme, String location) {
    final package = model.packages.packageRootOf(path);
    if (scheme == 'asset') {
      // A Flutter asset key, relative to the package; other packages'
      // assets (`packages/...`) are not followed.
      final key = location.replaceFirst(RegExp('^/+'), '');
      return key.startsWith('packages/') ? null : ['$package/$key'];
    }
    if (scheme == 'file') {
      return [
        if (File(location).isAbsolute) location else '$package/$location',
      ];
    }
    final relative = location.replaceFirst(RegExp('^/+'), '');
    return [
      if (path
          .substring(package.length)
          .replaceAll(r'\', '/')
          .startsWith('/test/'))
        '$package/test/resources/$relative',
      '$package/lib/resources/$relative',
    ];
  }

  @override
  void problems(StringContext string, List<Problem> problems) {
    final value = string.value.trim();
    if (!value.startsWith('asset:') ||
        string.annotationType != 'Value' ||
        value.contains(r'${') ||
        value.contains('#{')) {
      return;
    }
    final key = value
        .substring('asset:'.length)
        .replaceFirst(RegExp('^/+'), '');
    if (key.isEmpty || key.startsWith('packages/')) {
      return;
    }
    final package = model.packages.packageRootOf(string.path);
    final range = model.locations.rangeOf(
      string.file,
      string.contentStart,
      string.contentEnd,
    );
    if (!File('$package/$key').existsSync()) {
      problems.add(Problem(range, 'No file $key in this package'));
      return;
    }
    if (!declaredAsset(model.assets.of(package), key)) {
      final directory = key.contains('/')
          ? '${key.substring(0, key.lastIndexOf('/'))}/'
          : key;
      problems.add(
        Problem(
          range,
          '$key is not declared in pubspec.yaml, so the app would not '
          'contain it: add `- $directory` under `flutter: assets:`',
        ),
      );
    }
  }
}
