import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_core_dart/src/core/io/file_system_resource.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';

/// A file of the application's `lib/resources/` folder, embedded into the
/// generated code at build time.
///
/// Generated modules carry them (`BeanModule(resources: ...)`), so
/// `classpath:` locations work the same in `dart run`, AOT executables,
/// Flutter and the web — no Flutter asset declarations needed.
final class EmbeddedResource {
  /// A text file.
  const EmbeddedResource.text(String this.text) : base64 = null;

  /// A binary file, base64-encoded.
  const EmbeddedResource.base64(String this.base64) : text = null;

  /// Content of a text file.
  final String? text;

  /// Base64 content of a binary file.
  final String? base64;

  /// The content as bytes.
  Uint8List get bytes => text != null
      ? Uint8List.fromList(utf8.encode(text!))
      : base64Decode(base64!);
}

/// The `classpath:` resources of the application, like the classpath
/// resources of a Java application (`src/main/resources`).
///
/// Files under `lib/resources/` are embedded by the generator and
/// registered here when the generated module is created; when a path is not
/// embedded (e.g. while developing without regenerating), the file
/// `lib/resources/<path>` is read from disk.
///
/// Directories added with [addDirectory] come first, like `src/test/resources`
/// before `src/main/resources` on a test classpath: a file there shadows the
/// embedded file with the same path.
///
/// ```dart
/// final resource = DefaultResourceLoader().getResource('classpath:banner.txt');
/// print(resource.readAsStringSync());
/// ```
///
/// Spring (Java):
/// ```java
/// Resource resource = new ClassPathResource("banner.txt");
/// ```
abstract final class ClasspathResources {
  /// The location prefix, `classpath:`.
  static const prefix = 'classpath:';

  /// Directory read from disk for paths that are not embedded.
  static const directory = 'lib/resources';

  static final _embedded = <String, EmbeddedResource>{};
  static final _owners = <String, String>{};
  static final _directories = <String>[];

  /// Searches [directory] (on disk) before the embedded files, until the
  /// returned function is called. The most recently added directory comes
  /// first. Used by `spring_boot_starter_test` for `test/resources/`.
  ///
  /// ```dart
  /// final remove = ClasspathResources.addDirectory('test/resources');
  /// ...
  /// remove();
  /// ```
  static void Function() addDirectory(String directory) {
    final entry = directory.endsWith('/')
        ? directory.substring(0, directory.length - 1)
        : directory;
    _directories.insert(0, entry);
    var removed = false;
    return () {
      if (!removed) {
        removed = true;
        _directories.remove(entry);
      }
    };
  }

  /// Directories searched before the embedded files, first one first.
  static List<String> get directories => List.unmodifiable(_directories);

  /// Registers embedded files (path relative to `lib/resources/`); the
  /// first registration of a path wins, like the first classpath entry.
  ///
  /// With an [owner] (the module name), registering again replaces that
  /// owner's previous files — how a module rebuilt after a hot reload
  /// brings its changed `application.properties`.
  static void registerAll(
    Map<String, EmbeddedResource> resources, {
    String? owner,
  }) {
    if (owner != null) {
      _owners.removeWhere((path, previous) {
        final mine = previous == owner;
        if (mine) {
          _embedded.remove(path);
        }
        return mine;
      });
    }
    for (final MapEntry(:key, :value) in resources.entries) {
      final path = _normalize(key);
      if (_embedded.containsKey(path)) {
        continue;
      }
      _embedded[path] = value;
      if (owner != null) {
        _owners[path] = owner;
      }
    }
  }

  /// Paths of the embedded files.
  static Iterable<String> get paths => _embedded.keys;

  /// The resource for `classpath:<path>` (or a plain [path]).
  static Resource resolve(String path) {
    final normalized = _normalize(
      path.startsWith(prefix) ? path.substring(prefix.length) : path,
    );
    for (final directory in _directories) {
      final file = FileSystemResource('$directory/$normalized');
      if (file.exists()) {
        return file;
      }
    }
    final embedded = _embedded[normalized];
    final description = 'class path resource [$normalized]';
    if (embedded != null) {
      return ByteArrayResource(embedded.bytes, description: description);
    }
    return FileSystemResource('$directory/$normalized');
  }

  // `/config/./app.properties` → `config/app.properties`.
  static String _normalize(String path) =>
      FileSystemResource(path).path.replaceFirst(RegExp('^/'), '');
}
