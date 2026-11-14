import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

/// Where the scene assets a build makes are kept in the app, from its
/// root: inside `lib/spring_gen/`, with everything else that is generated.
///
/// The folder's own name is the engine's: at run time `flutter_scene`
/// finds its generated assets by the end of their address
/// (`.../flutter_scene_generated/manifest.json`), wherever that is.
const String sceneGeneratedDirectory = 'lib/spring_gen/flutter_scene_generated';

const String _engineDirectory = 'flutter_scene_generated';
const String _stageDirectory = '.dart_tool/spring_scene';

/// The place the engine's build hooks work in, and the move of what they
/// made into the app's `lib/spring_gen/`.
///
/// `flutter_scene` writes its generated assets into a folder at the root
/// of the package its hook runs for, and checks that package's
/// `pubspec.yaml` for it: neither can be told another place. So its hooks
/// are run for a stand-in of the app under `.dart_tool/spring_scene/` (a
/// `pubspec.yaml` with the asset entries, the app's source folders linked
/// in), and what they wrote there is copied to [sceneGeneratedDirectory].
/// The app's tree gets no folder of the engine's at its root.
final class SceneStage {
  /// The stage of the app [input] is for.
  SceneStage(this.input)
    : app = Directory.fromUri(input.packageRoot).absolute.path;

  /// The app's own hook input.
  final BuildInput input;

  /// The app's root.
  final String app;

  /// The stand-in's root.
  String get root => p.join(app, _stageDirectory);

  /// The app's folder the generated assets end in.
  String get generated =>
      p.joinAll([app, ...sceneGeneratedDirectory.split('/')]);

  /// The asset entries of [pubspec] (its text) under
  /// [sceneGeneratedDirectory], as the engine names them: the folder
  /// itself (`''`) and each folder of a kind of platform (`opengl_es`).
  static Set<String> entriesOf(String pubspec) {
    final entry = RegExp(
      '${RegExp.escape(sceneGeneratedDirectory)}/(?:([A-Za-z0-9_]+)/)?'
      r'''\s*(?:['"]?\s*)?(?:#.*)?$''',
    );
    return {
      for (final line in pubspec.split('\n'))
        if (!line.trimLeft().startsWith('#'))
          if (entry.firstMatch(line.trimRight()) case final match?)
            match[1] ?? '',
    };
  }

  /// Makes the stand-in ready and gives the hook input the engine's hooks
  /// are run with: the app's, rooted at the stand-in.
  ///
  /// [sources] are the app's folders the hooks read sources from
  /// (`assets`): each is linked into the stand-in under its own name, so
  /// a source keeps the address the app loads it by
  /// (`assets/materials/glow.fmat`).
  BuildInput prepare({Iterable<String> sources = const ['assets']}) {
    final pubspec = File(p.join(app, 'pubspec.yaml'));
    final entries = entriesOf(pubspec.readAsStringSync());
    if (!entries.contains('')) {
      throw StateError(
        'The pubspec.yaml of ${input.packageName} does not list the scene '
        'assets the build makes. Add to it:\n'
        'flutter:\n'
        '  assets:\n'
        '    - $sceneGeneratedDirectory/\n'
        '    - path: $sceneGeneratedDirectory/opengl_es/\n'
        '      platforms: [web]\n',
      );
    }
    Directory(root).createSync(recursive: true);
    _write(
      p.join(root, 'pubspec.yaml'),
      'name: ${input.packageName}\n'
      'flutter:\n'
      '  assets:\n'
      '${[for (final entry in entries) '    - $_engineDirectory/${entry.isEmpty ? '' : '$entry/'}\n'].join()}',
    );
    for (final source in sources) {
      _link(p.join(app, source), p.join(root, source));
    }
    return BuildInput({...input.json, 'package_root': '$root${p.separator}'});
  }

  /// Copies what the engine's hooks made in the stand-in to
  /// [sceneGeneratedDirectory]: new and changed files are written, the
  /// ones no longer made are removed. A file that did not change is left
  /// alone, so the app's asset bundle is not built again for it.
  void publish() {
    final from = Directory(p.join(root, _engineDirectory));
    final to = Directory(generated);
    if (!from.existsSync()) {
      if (to.existsSync()) {
        to.deleteSync(recursive: true);
      }
      return;
    }
    to.createSync(recursive: true);
    final made = <String>{};
    for (final entity in from.listSync(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: from.path);
      made.add(relative);
      final target = p.join(to.path, relative);
      if (entity is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entity is File && !_same(entity, File(target))) {
        File(target).parent.createSync(recursive: true);
        entity.copySync(target);
      }
    }
    for (final entity in to.listSync(recursive: true, followLinks: false)) {
      if (!made.contains(p.relative(entity.path, from: to.path)) &&
          entity.existsSync()) {
        entity.deleteSync(recursive: true);
      }
    }
  }

  static bool _same(File a, File b) {
    if (!b.existsSync() || a.lengthSync() != b.lengthSync()) {
      return false;
    }
    final left = a.readAsBytesSync();
    final right = b.readAsBytesSync();
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }
    return true;
  }

  static void _write(String path, String text) {
    final file = File(path);
    if (!file.existsSync() || file.readAsStringSync() != text) {
      file.writeAsStringSync(text);
    }
  }

  // A link to the app's folder; where links cannot be made (Windows
  // without the right to), a copy of it, made again each time.
  static void _link(String source, String target) {
    final type = FileSystemEntity.typeSync(target, followLinks: false);
    if (!Directory(source).existsSync()) {
      if (type != FileSystemEntityType.notFound) {
        _remove(target, type);
      }
      return;
    }
    if (type == FileSystemEntityType.link) {
      try {
        if (Link(target).resolveSymbolicLinksSync() ==
            Directory(source).resolveSymbolicLinksSync()) {
          return;
        }
      } on FileSystemException {
        // A link to a folder that is gone: made again below.
      }
    }
    if (type != FileSystemEntityType.notFound) {
      _remove(target, type);
    }
    Directory(p.dirname(target)).createSync(recursive: true);
    try {
      Link(target).createSync(source);
    } on FileSystemException {
      _copy(Directory(source), Directory(target));
    }
  }

  static void _remove(String path, FileSystemEntityType type) {
    if (type == FileSystemEntityType.link) {
      Link(path).deleteSync();
    } else {
      Directory(path).deleteSync(recursive: true);
    }
  }

  static void _copy(Directory from, Directory to) {
    to.createSync(recursive: true);
    for (final entity in from.listSync(recursive: true)) {
      final target = p.join(to.path, p.relative(entity.path, from: from.path));
      if (entity is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entity is File) {
        File(target).parent.createSync(recursive: true);
        entity.copySync(target);
      }
    }
  }
}
