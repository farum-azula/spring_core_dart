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
/// `file:` and classpath locations (`classpath:` or no prefix, as in
/// [DefaultResourceLoader]); other locations are delegated to
/// [resourceLoader] without wildcard expansion.
///
/// Results are sorted by path. There is no `classpath*:` support.
///
/// ```dart
/// final resolver = PathMatchingResourcePatternResolver();
/// for (final resource in resolver.getResources('file:config/*.properties')) {
///   environment.propertySources.addLast(
///     ResourcePropertySource.fromResource(resource),
///   );
/// }
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
/// ```
class PathMatchingResourcePatternResolver implements ResourcePatternResolver {
  /// Creates a resolver; [resourceLoader] defaults to
  /// [DefaultResourceLoader] and [pathMatcher] to [AntPathMatcher].
  PathMatchingResourcePatternResolver({
    ResourceLoader? resourceLoader,
    PathMatcher? pathMatcher,
  }) : resourceLoader = resourceLoader ?? DefaultResourceLoader(),
       pathMatcher = pathMatcher ?? AntPathMatcher();

  /// Loads single resources and non-file locations.
  final ResourceLoader resourceLoader;

  /// Matches file paths against the pattern.
  final PathMatcher pathMatcher;

  @override
  Resource getResource(String location) => resourceLoader.getResource(location);

  @override
  List<Resource> getResources(String locationPattern) {
    final isFile = locationPattern.startsWith(ResourceLoader.filePrefix);
    // Plain locations are classpath locations, as in DefaultResourceLoader.
    final isClasspath =
        locationPattern.startsWith(ClasspathResources.prefix) ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(locationPattern);
    final path = isFile
        ? locationPattern.substring(ResourceLoader.filePrefix.length)
        : locationPattern.startsWith(ClasspathResources.prefix)
        ? locationPattern.substring(ClasspathResources.prefix.length)
        : locationPattern;
    if (!(isFile || isClasspath) || !pathMatcher.isPattern(path)) {
      final resource = getResource(locationPattern);
      return resource.exists() ? [resource] : const [];
    }
    if (isClasspath) {
      return _classpathResources(path.replaceFirst(RegExp('^/+'), ''));
    }
    // Walk the directory before the first wildcard segment and match the
    // remaining pattern against paths relative to it.
    final root = _rootDirectory(path);
    final directory = root.isEmpty ? '.' : root;
    if (!FileAccess.isDirectory(directory)) {
      return const [];
    }
    final subPattern = path.substring(root.length);
    final prefix = directory.endsWith('/') ? directory : '$directory/';
    return [
      for (final file in FileAccess.listFilesRecursively(directory))
        if (_relative(file, prefix) case final relative?
            when pathMatcher.match(subPattern, relative))
          FileSystemResource(file),
    ];
  }

  // Classpath paths matching [pattern]: the files of the classpath
  // directories and the embedded resources, each resolved like
  // `classpath:<path>` (so the first directory having it wins).
  List<Resource> _classpathResources(String pattern) {
    final paths = <String>{
      ...ClasspathResources.paths,
      for (final directory in {
        ...ClasspathResources.directories,
        ClasspathResources.directory,
      })
        if (FileAccess.isDirectory(directory))
          for (final file in FileAccess.listFilesRecursively(directory))
            ?_relative(file, '$directory/'),
    };
    return [
      for (final path in paths.toList()..sort())
        if (pathMatcher.match(pattern, path)) ClasspathResources.resolve(path),
    ];
  }

  // The directory part (with trailing `/`) before the first segment with
  // wildcards; empty when the pattern starts with one.
  String _rootDirectory(String path) {
    var end = path.length;
    while (end > 0 && pathMatcher.isPattern(path.substring(0, end))) {
      end = path.lastIndexOf('/', end - 2) + 1;
    }
    return path.substring(0, end);
  }

  // [file] relative to the directory [prefix], or `null` if outside it.
  // `./` is stripped from both, since listings of `.` yield `./x` paths.
  static String? _relative(String file, String prefix) {
    final normalized = file.startsWith('./') ? file.substring(2) : file;
    final normalizedPrefix = prefix.startsWith('./')
        ? prefix.substring(2)
        : prefix == './'
        ? ''
        : prefix;
    if (normalizedPrefix.isEmpty) {
      return normalized;
    }
    return normalized.startsWith(normalizedPrefix)
        ? normalized.substring(normalizedPrefix.length)
        : null;
  }
}
