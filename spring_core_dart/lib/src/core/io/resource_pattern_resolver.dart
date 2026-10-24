import 'package:spring_core_dart/src/core/io/file_access_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/io/file_access_io.dart';
import 'package:spring_core_dart/src/core/io/classpath_resources.dart';
import 'package:spring_core_dart/src/core/io/file_system_resource.dart';
import 'package:spring_core_dart/src/core/io/path_matcher.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';

/// Resolves location patterns to several resources, like Spring's
/// `ResourcePatternResolver`.
///
/// ```dart
/// final ResourcePatternResolver resolver =
///     PathMatchingResourcePatternResolver();
/// final files = resolver.getResources('file:config/**/*.properties');
/// ```
///
/// Spring (Java):
/// ```java
/// ResourcePatternResolver resolver =
///     new PathMatchingResourcePatternResolver();
/// Resource[] files = resolver.getResources("file:config/**/*.properties");
/// ```
abstract interface class ResourcePatternResolver implements ResourceLoader {
  /// Resources matching [locationPattern]; a location without wildcards
  /// yields that single resource (if it exists).
  ///
  /// Unlike Spring, a missing non-pattern location gives an empty list.
  List<Resource> getResources(String locationPattern);
}

/// Ant-style patterns such as `file:config/**/*.properties` or
/// `classpath:i18n/*.properties`, like Spring's
/// `PathMatchingResourcePatternResolver`. Patterns are supported for
/// `file:` and classpath locations (`classpath:`, `classpath*:` or no
/// prefix, as in [DefaultResourceLoader]); other locations are delegated
/// to [resourceLoader] without wildcard expansion.
///
/// The classpath roots are the directories added with
/// `ClasspathResources.addDirectory` (latest first), then the embedded
/// resources together with `lib/resources/`. As in Spring, a `classpath:`
/// pattern searches only the first root that has its base directory,
/// while `classpath*:` searches every root, and `classpath*:` without
/// wildcards gives the resource of every root that has it.
///
/// Matching files and directories are returned, sorted by path within a
/// root; directories the pattern cannot match below are not walked.
///
/// ```dart
/// final resolver = PathMatchingResourcePatternResolver();
/// for (final resource in resolver.getResources('file:config/*.properties')) {
///   environment.propertySources.addLast(
///     ResourcePropertySource.fromResource(resource),
///   );
/// }
/// resolver.getResources('classpath*:i18n/messages*.properties');
/// ```
///
/// Spring (Java):
/// ```java
/// var resolver = new PathMatchingResourcePatternResolver();
/// Resource[] files = resolver.getResources("file:config/*.properties");
/// for (Resource resource : files) {
///   environment.getPropertySources()
///       .addLast(new ResourcePropertySource(resource));
/// }
/// resolver.getResources("classpath*:i18n/messages*.properties");
/// ```
class PathMatchingResourcePatternResolver implements ResourcePatternResolver {
  /// Creates a resolver; [resourceLoader] defaults to
  /// [DefaultResourceLoader] and [pathMatcher] to [AntPathMatcher].
  PathMatchingResourcePatternResolver({
    ResourceLoader? resourceLoader,
    PathMatcher? pathMatcher,
  }) : resourceLoader = resourceLoader ?? DefaultResourceLoader(),
       pathMatcher = pathMatcher ?? AntPathMatcher();

  /// Prefix searching every classpath root, like Spring's
  /// `CLASSPATH_ALL_URL_PREFIX`.
  static const classpathAllUrlPrefix = 'classpath*:';

  /// Loads single resources and non-file locations.
  final ResourceLoader resourceLoader;

  /// Matches file paths against the pattern.
  final PathMatcher pathMatcher;

  @override
  Resource getResource(String location) => resourceLoader.getResource(location);

  @override
  List<Resource> getResources(String locationPattern) {
    if (locationPattern.startsWith(classpathAllUrlPrefix)) {
      final path = _classpathPath(
        locationPattern.substring(classpathAllUrlPrefix.length),
      );
      if (!pathMatcher.isPattern(path)) {
        return [
          for (final root in _roots())
            if (root.resolve(path) case final resource when resource.exists())
              resource,
        ];
      }
      return [for (final root in _roots()) ..._matches(root, path)];
    }
    final isFile = locationPattern.startsWith(ResourceLoader.filePrefix);
    // Plain locations are classpath locations, as in DefaultResourceLoader.
    final isClasspath =
        locationPattern.startsWith(ClasspathResources.prefix) ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(locationPattern);
    final path = isFile
        ? FileSystemResource.fromFileUrl(locationPattern).path
        : locationPattern.startsWith(ClasspathResources.prefix)
        ? locationPattern.substring(ClasspathResources.prefix.length)
        : locationPattern;
    if (!(isFile || isClasspath) || !pathMatcher.isPattern(path)) {
      final resource = getResource(locationPattern);
      return resource.exists() ? [resource] : const [];
    }
    if (isClasspath) {
      final pattern = _classpathPath(path);
      final base = _rootDirectory(pattern);
      for (final root in _roots()) {
        if (root.hasDirectory(base)) {
          return _matches(root, pattern);
        }
      }
      return const [];
    }
    // Walk the directory before the first wildcard segment and match the
    // remaining pattern against paths relative to it.
    final root = _rootDirectory(path);
    final directory = root.isEmpty ? '.' : root;
    if (!FileAccess.isDirectory(directory)) {
      return const [];
    }
    final prefix = directory.endsWith('/') ? directory : '$directory/';
    return [
      for (final relative in _walk(directory, path.substring(root.length)))
        FileSystemResource('$prefix$relative'),
    ];
  }

  // A classpath path without leading slashes.
  static String _classpathPath(String path) =>
      path.replaceFirst(RegExp('^/+'), '');

  // The classpath roots, in lookup order.
  List<_ClasspathRoot> _roots() => [
    for (final directory in ClasspathResources.directories)
      _DirectoryRoot(directory),
    _EmbeddedRoot(),
  ];

  // The resources of [root] matching [pattern], sorted by path.
  List<Resource> _matches(_ClasspathRoot root, String pattern) {
    final base = _rootDirectory(pattern);
    return [
      for (final path in root.paths(this, base, pattern.substring(base.length)))
        root.resolve(path),
    ];
  }

  // Paths below [directory], relative to it, that match [pattern]: files
  // and directories, sorted. A directory is only entered when the pattern
  // can still match below it (`matchStart`), like Spring's
  // doRetrieveMatchingFiles.
  List<String> _walk(String directory, String pattern) {
    final result = <String>[];
    final prefix = directory.endsWith('/') ? directory : '$directory/';
    void visit(String relativeDirectory) {
      final current = relativeDirectory.isEmpty
          ? directory
          : '$prefix$relativeDirectory';
      for (final file in FileAccess.listFiles(current)) {
        final relative = '$relativeDirectory${_name(file)}';
        if (pathMatcher.match(pattern, relative)) {
          result.add(relative);
        }
      }
      for (final subdirectory in FileAccess.listDirectories(current)) {
        final relative = '$relativeDirectory${_name(subdirectory)}';
        if (pathMatcher.match(pattern, relative)) {
          result.add(relative);
        }
        if (pathMatcher.matchStart(pattern, '$relative/')) {
          visit('$relative/');
        }
      }
    }

    visit('');
    return result..sort();
  }

  static String _name(String path) => path.substring(path.lastIndexOf('/') + 1);

  // The directory part (with trailing `/`) before the first segment with
  // wildcards; empty when the pattern starts with one.
  String _rootDirectory(String path) {
    var end = path.length;
    while (end > 0 && pathMatcher.isPattern(path.substring(0, end))) {
      end = path.lastIndexOf('/', end - 2) + 1;
    }
    return path.substring(0, end);
  }
}

// One classpath root: a directory, or the embedded resources together
// with `lib/resources/`.
sealed class _ClasspathRoot {
  // Whether the root has the directory [base] (`config/`; `''` is the
  // root itself).
  bool hasDirectory(String base);

  // Paths in the root below [base] whose rest matches [pattern], sorted.
  Iterable<String> paths(
    PathMatchingResourcePatternResolver resolver,
    String base,
    String pattern,
  );

  // The resource at [path] in this root.
  Resource resolve(String path);
}

final class _DirectoryRoot extends _ClasspathRoot {
  _DirectoryRoot(this.directory);

  final String directory;

  @override
  bool hasDirectory(String base) => FileAccess.isDirectory('$directory/$base');

  @override
  Iterable<String> paths(
    PathMatchingResourcePatternResolver resolver,
    String base,
    String pattern,
  ) => hasDirectory(base)
      ? [
          for (final relative in resolver._walk('$directory/$base', pattern))
            '$base$relative',
        ]
      : const [];

  @override
  Resource resolve(String path) => FileSystemResource('$directory/$path');
}

final class _EmbeddedRoot extends _ClasspathRoot {
  static const _directory = ClasspathResources.directory;

  @override
  bool hasDirectory(String base) =>
      base.isEmpty ||
      ClasspathResources.paths.any((path) => path.startsWith(base)) ||
      FileAccess.isDirectory('$_directory/$base');

  @override
  Iterable<String> paths(
    PathMatchingResourcePatternResolver resolver,
    String base,
    String pattern,
  ) => {
    for (final path in ClasspathResources.paths)
      if (path.startsWith(base) &&
          resolver.pathMatcher.match(pattern, path.substring(base.length)))
        path,
    if (FileAccess.isDirectory('$_directory/$base'))
      for (final relative in resolver._walk('$_directory/$base', pattern))
        '$base$relative',
  }.toList()..sort();

  // The embedded copy first, then the file under `lib/resources/`.
  @override
  Resource resolve(String path) {
    if (ClasspathResources.paths.contains(path)) {
      return ClasspathResources.resolveEmbedded(path);
    }
    return FileSystemResource('$_directory/$path');
  }
}
