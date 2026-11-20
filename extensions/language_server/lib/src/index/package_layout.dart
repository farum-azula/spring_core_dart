import 'dart:io';

/// Where the packages of the workspace are: the package a file belongs to,
/// with symlinks resolved where packages are compared, and paths shown
/// relative to the workspace folders.
final class PackageLayout {
  /// The layout of the packages under [roots].
  PackageLayout(this.roots);

  /// The workspace folders the editor opened.
  final List<String> roots;

  final _packageRoots = <String, String>{};
  final _ownPackages = <String, String?>{};

  /// Forgets the package roots found so far: a `pubspec.yaml` may have
  /// appeared or gone. The scan calls it each time it runs.
  void forgetRoots() => _packageRoots.clear();

  /// The root directory of the package of the file [path]: the nearest
  /// directory with a `pubspec.yaml` inside the workspace folders, else the
  /// workspace folder itself.
  String packageRootOf(String path) {
    final directory = File(path).parent.path;
    return _packageRoots[directory] ??= () {
      var current = Directory(directory);
      while (true) {
        if (File('${current.path}/pubspec.yaml').existsSync()) {
          return current.path;
        }
        final parent = current.parent;
        if (parent.path == current.path ||
            !roots.any((root) => parent.path.startsWith(root))) {
          break;
        }
        current = parent;
      }
      return roots.firstWhere(path.startsWith, orElse: () => directory);
    }();
  }

  /// The folder of the nearest `pubspec.yaml` above [path], wherever it is,
  /// symlinks resolved; `null` when there is none. A package nested in
  /// another (an example inside a starter) has its own.
  String? ownPackageOf(String path) =>
      _ownPackages[File(path).parent.path] ??= () {
        var current = Directory(File(path).parent.path);
        while (true) {
          if (File('${current.path}/pubspec.yaml').existsSync()) {
            return realPath(current.path);
          }
          if (current.parent.path == current.path) {
            return null;
          }
          current = current.parent;
        }
      }();

  /// [path] with symlinks resolved and without a trailing slash; [path]
  /// itself when it cannot be resolved.
  static String realPath(String path) {
    final trimmed = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    try {
      return Directory(trimmed).resolveSymbolicLinksSync();
    } on FileSystemException {
      return trimmed;
    }
  }

  /// [path] relative to the workspace folder it is in, as hovers show it;
  /// [path] itself when it is in none.
  String shortPath(String path) {
    for (final root in roots) {
      if (path.startsWith(root)) {
        return path.substring(root.length).replaceFirst(RegExp(r'^[/\\]'), '');
      }
    }
    return path;
  }

  /// Whether [path] is inside a `resources/` directory.
  static bool inResources(String path) =>
      path.replaceAll(r'\', '/').contains('/resources/');

  /// The path of [path] below its `resources/` directory, without the
  /// extension: `i18n/messages_ja` for
  /// `.../lib/resources/i18n/messages_ja.properties`; `null` outside one.
  static String? resourcePath(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final index = normalized.lastIndexOf('/resources/');
    if (index < 0) {
      return null;
    }
    final relative = normalized.substring(index + '/resources/'.length);
    return relative.substring(0, relative.lastIndexOf('.'));
  }
}
