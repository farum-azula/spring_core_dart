import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_core_dart/src/core/io/file_system_resource.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';

/// The content of one file of `lib/resources/`, written into the generated
/// code at build time.
///
/// Embedding is what makes `classpath:` locations work the same in
/// `dart run`, AOT executables, Flutter and the web, where there is no
/// project folder at run time and no asset declaration is needed. The
/// generator writes these (`BeanModule(resources: ...)`); applications
/// never create one.
final class EmbeddedResource {
  /// A text file with the content [text].
  const EmbeddedResource.text(String this.text) : base64 = null;

  /// A binary file whose content is encoded in base64.
  const EmbeddedResource.base64(String this.base64) : text = null;

  /// The content of a text file; `null` for a binary file.
  final String? text;

  /// The base64 content of a binary file; `null` for a text file.
  final String? base64;

  /// The content as bytes (text encoded as UTF-8).
  Uint8List get bytes => text != null
      ? Uint8List.fromList(utf8.encode(text!))
      : base64Decode(base64!);
}

/// The registry behind `classpath:` locations: the files of
/// `lib/resources/` of the application and of its dependencies.
///
/// Dart has no classpath, so the generator embeds every file of a
/// package's `lib/resources/` into its generated module, and the files are
/// registered here when the module is created. That is how
/// `application.yml`, message bundles and templates are found on every
/// platform. A path that is not embedded (a file added while developing
/// without regenerating) is read from `lib/resources/<path>` on disk.
/// Directories added with [addDirectory] come first, like
/// `src/test/resources` before `src/main/resources` on a test classpath: a
/// file there shadows the embedded file with the same path.
///
/// Applications only write locations (`classpath:templates/mail.txt`);
/// resource loaders call this class. Code calls it directly in tests, to
/// add a directory, or to list the embedded files.
///
/// ```dart
/// // Reads lib/resources/banner.txt, embedded or from disk.
/// final resource =
///     DefaultResourceLoader().getResource('classpath:banner.txt');
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

  /// The directory read from disk for paths that are not embedded:
  /// `lib/resources`, relative to the working directory.
  static const directory = 'lib/resources';

  static final _embedded = <String, EmbeddedResource>{};
  static final _owners = <String, String>{};
  static final _directories = <String>[];

  /// Makes `classpath:` look in [directory] on disk before the embedded
  /// files, until the returned function is called. The most recently
  /// added directory comes first. `spring_boot_starter_test` uses it for
  /// `test/resources/`, so test config files win over packaged ones.
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

  /// The directories searched before the embedded files, in search order.
  static List<String> get directories => List.unmodifiable(_directories);

  /// Registers embedded files, keyed by their path under
  /// `lib/resources/`. Generated modules call it; applications do not.
  ///
  /// The first registration of a path wins, as the first classpath entry
  /// does in Java. With an [owner] (the module name),
  /// registering again replaces that owner's earlier files: that is how a
  /// module rebuilt after a hot reload brings its changed
  /// `application.properties`.
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

  /// The paths of all embedded files, relative to `lib/resources/`.
  static Iterable<String> get paths => _embedded.keys;

  /// The resource for `classpath:<path>` or a plain [path]: a file of an
  /// added directory when it exists there, otherwise the embedded file,
  /// otherwise the file under [directory] (which may not exist).
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
    return resolveEmbedded(normalized);
  }

  /// The resource for [path], ignoring the added [directories]: the
  /// embedded file, or else the file under [directory].
  ///
  /// ```dart
  /// ClasspathResources.resolveEmbedded('application.yml');
  /// ```
  static Resource resolveEmbedded(String path) {
    final normalized = _normalize(path);
    final embedded = _embedded[normalized];
    if (embedded != null) {
      return _EmbeddedClasspathResource(normalized, embedded.bytes);
    }
    return FileSystemResource('$directory/$normalized');
  }

  // `/config/./app.properties` → `config/app.properties`.
  static String _normalize(String path) =>
      FileSystemResource(path).path.replaceFirst(RegExp('^/'), '');
}

// An embedded file, with a file name and relative resources like Spring's
// ClassPathResource.
final class _EmbeddedClasspathResource extends ByteArrayResource {
  _EmbeddedClasspathResource(this.path, Uint8List bytes)
    : super(bytes, description: 'class path resource [$path]');

  final String path;

  @override
  String get filename => path.substring(path.lastIndexOf('/') + 1);

  @override
  Resource createRelative(String relativePath) {
    final slash = path.lastIndexOf('/');
    final directory = slash < 0 ? '' : path.substring(0, slash + 1);
    final relative = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    return ClasspathResources.resolve('$directory$relative');
  }
}
