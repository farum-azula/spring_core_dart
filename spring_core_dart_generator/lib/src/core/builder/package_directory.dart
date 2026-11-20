import 'dart:convert';
import 'dart:io' as io;

import 'package:build/build.dart';
import 'package:pub_semver/pub_semver.dart';

/// Finds the directory of a package on disk, for the few files the
/// builders read or write outside build_runner's assets: the generated
/// file kept while the sources have errors, an asset the build does not
/// see, `web_dev_config.yaml`.
///
/// Such a file must be looked up in the directory of the package being
/// built, not in the working directory: `build_runner build --workspace`
/// builds every package of a pub workspace from one directory, so a path
/// relative to it would read (and write back) another package's file.
/// build_runner gives builders `asset:` package roots
/// (`BuildStep.packageConfig`), so the directory comes from the nearest
/// `.dart_tool/package_config.json` at or above the working directory:
/// the package's own, or its workspace's.
///
/// ```dart
/// final file = PackageDirectories.current.file(
///   AssetId('app', 'lib/spring_gen/main.spring.dart'),
/// );
/// ```
///
/// Spring has no counterpart: Spring's annotation processing runs inside
/// the compiler, on one module at a time.
final class PackageDirectories {
  /// Looks packages up from the directory `workingDirectory` (the current
  /// directory by default; tests pass a directory of their own).
  PackageDirectories({this._workingDirectory});

  /// The directories seen from the current directory, cached for the
  /// build.
  static final current = PackageDirectories();

  final io.Directory? _workingDirectory;

  final _directories = <String, Uri?>{};

  /// The root directory of [package], ending with `/`; `null` when no
  /// `.dart_tool/package_config.json` above the working directory lists
  /// it or the package is not on the local file system.
  Uri? directoryOf(String package) =>
      _directories.putIfAbsent(package, () => _find(package));

  /// The file of [id] in its package's directory, or `null` when the
  /// directory is not known.
  io.File? file(AssetId id) {
    final directory = directoryOf(id.package);
    return directory == null
        ? null
        : io.File.fromUri(directory.resolveUri(Uri(path: id.path)));
  }

  /// The content of the file of [id], or `null` when there is none or its
  /// package's directory is not known.
  Future<String?> read(AssetId id) async {
    final file = this.file(id);
    return file != null && file.existsSync() ? await file.readAsString() : null;
  }

  /// The language version of [package] (`3.13`, as `3.13.0`), as its
  /// package config gives it; `null` when it gives none or does not list
  /// the package.
  Version? languageVersionOf(String package) {
    final entry = _entries.putIfAbsent(package, () => _entry(package));
    final version = entry?['languageVersion'];
    if (version is! String) {
      return null;
    }
    return switch (version.split('.').map(int.tryParse).toList()) {
      [final int major, final int minor] => Version(major, minor, 0),
      _ => null,
    };
  }

  final _entries = <String, Map<Object?, Object?>?>{};

  Uri? _find(String package) {
    final entry = _entries.putIfAbsent(package, () => _entry(package));
    if (entry == null) {
      return null;
    }
    final root = (entry['config']! as Uri).resolve(entry['rootUri']! as String);
    if (!root.isScheme('file')) {
      return null;
    }
    return root.path.endsWith('/') ? root : Uri.parse('$root/');
  }

  // The entry of [package] in the nearest `.dart_tool/package_config.json`
  // at or above the working directory, with the config's own URI under
  // `config`; `null` when it does not list the package or cannot be read.
  Map<Object?, Object?>? _entry(String package) {
    var directory = (_workingDirectory ?? io.Directory.current).absolute;
    while (true) {
      final config = io.File.fromUri(
        directory.uri.resolve('.dart_tool/package_config.json'),
      );
      if (config.existsSync()) {
        try {
          final json = jsonDecode(config.readAsStringSync()) as Map;
          for (final entry in json['packages'] as List) {
            if (entry is Map &&
                entry['name'] == package &&
                entry['rootUri'] is String) {
              return {...entry, 'config': config.uri};
            }
          }
        } on Object {
          // Unreadable: the package's directory is unknown.
        }
        return null;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        return null;
      }
      directory = parent;
    }
  }
}
