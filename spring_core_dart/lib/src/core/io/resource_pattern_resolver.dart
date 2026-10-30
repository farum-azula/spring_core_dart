import 'package:spring_core_dart/src/core/io/classpath_resources.dart';
import 'package:spring_core_dart/src/core/io/file_access_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/io/file_access_io.dart';
import 'package:spring_core_dart/src/core/io/file_system_resource.dart';
import 'package:spring_core_dart/src/core/io/path_matcher.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';

/// A [ResourceLoader] that also finds all resources matching a pattern
/// with wildcards, such as `classpath:templates/*.html` or
/// `file:config/**/*.properties`.
///
/// Use it to load every file of a kind without listing them: all
/// templates, all seed data files, all message bundles. The application
/// context is one, so a constructor parameter of type
/// `ResourcePatternResolver` receives it.
///
/// ```dart
/// @Component()
/// class Templates {
///   Templates(this.resources);
///   final ResourcePatternResolver resources; // the application context
///
///   // Every mail template shipped in lib/resources/mail/.
///   List<Resource> all() => resources.getResources('classpath:mail/*.txt');
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Component
/// class Templates {
///   private final ResourcePatternResolver resources;
///
///   Templates(ResourcePatternResolver resources) {
///     this.resources = resources;
///   }
///
///   Resource[] all() throws IOException {
///     return resources.getResources("classpath:mail/*.txt");
///   }
/// }
/// ```
abstract interface class ResourcePatternResolver implements ResourceLoader {
  /// All resources matching [locationPattern], possibly none. A location
  /// without wildcards gives that one resource when it exists.
  ///
  /// Unlike Spring, a missing location without wildcards gives an empty
  /// list instead of a resource that does not exist.
  List<Resource> getResources(String locationPattern);
}

/// The [ResourcePatternResolver] used everywhere: it expands Ant-style
/// patterns (`*`, `**`, `?`) in `file:` and classpath locations.
///
/// The application context uses one, so applications usually go through
/// the context; create one to search files without a context, in a tool
/// or a test. Patterns work for `file:` and classpath locations
/// (`classpath:`, `classpath*:` or no prefix, as in
/// [DefaultResourceLoader]); other locations go to [resourceLoader] as
/// they are, without wildcard expansion.
///
/// The classpath roots are the directories added with
/// `ClasspathResources.addDirectory` (latest first), then the embedded
/// resources together with `lib/resources/`. As in Spring, a `classpath:`
/// pattern searches only the first root that has its base directory,
/// while `classpath*:` searches every root, and `classpath*:` without
/// wildcards gives the resource of every root that has it.
///
/// Matching files and directories are returned, sorted by path within a
/// root; directories the pattern cannot match below are not walked. The
/// pattern is cleaned first, as Spring cleans it: the directory before
/// the first wildcard is normalized as a classpath location is
/// (`classpath:./mail/../mail//*.txt` is `classpath:mail/*.txt`), and in
/// the rest, as by Spring's `StringUtils.cleanPath`, `\\` (two
/// backslashes) is read as one `/`, then each `\` left as `/`, and `.` and
/// `..` segments are resolved (`classpath:mail\*.txt`,
/// `classpath:mail/*/../*.txt` and `classpath:mail/*\\..\\*.txt` are
/// `classpath:mail/*.txt`). As in Spring, a `{name:regex}` must not use
/// `\`, which becomes `/` (`classpath:mail/{n:\w+}.txt` matches nothing):
/// write character classes such as `[0-9]` or `[a-zA-Z0-9_]` instead.
/// As in Spring, the wildcards of a `file:` pattern are those written:
/// only the directory before the first one is percent-decoded
/// (`file:my%20dir/*.txt` searches `my dir/`), so `file:mail/%2A.txt` is
/// the one file named `*.txt`, and the rest matches a `%` as it is.
///
/// Kept differences from Spring 7:
///
/// - a `..` that climbs above the roots, or above the directory before
///   the first wildcard, finds nothing (Spring's
///   `classpath*:mail/../../*.txt` can reach files next to a classpath
///   directory; here nothing outside the roots is found);
/// - a `\` in the directory before the first wildcard of a `classpath*:`
///   pattern is cleaned too (`classpath*:conf\sub/*.txt` finds
///   `conf/sub/*.txt`, as `classpath:conf\sub/*.txt` does in both), where
///   Spring hands the name to Java's class loader, which refuses it;
/// - a `file:` pattern whose separators are `\` there is read the same
///   way, so Windows paths work (`file:lib\resources\mail\*.txt`,
///   `file:C:\config\*.properties`), where Spring on macOS and Linux
///   finds nothing (`Invalid URI [file:]`: its root directory ends at the
///   last `/`);
/// - a `classpath:` pattern whose base directory no root has
///   (`classpath:nodir/*.txt`) gives an empty list, where Spring throws a
///   `FileNotFoundException` (`cannot be resolved to URL because it does
///   not exist`).
///
/// ```dart
/// // A tool that adds every properties file of ./config/ to its
/// // environment, then finds the message bundles of all packages.
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
  /// Creates a resolver that loads single resources with [resourceLoader]
  /// (a [DefaultResourceLoader] unless given) and matches paths with
  /// [pathMatcher] (an [AntPathMatcher] unless given).
  PathMatchingResourcePatternResolver({
    ResourceLoader? resourceLoader,
    PathMatcher? pathMatcher,
  }) : resourceLoader = resourceLoader ?? DefaultResourceLoader(),
       pathMatcher = pathMatcher ?? AntPathMatcher();

  /// The prefix that searches every classpath root instead of the first
  /// one that has the base directory: `classpath*:`, Spring's
  /// `CLASSPATH_ALL_URL_PREFIX`.
  static const classpathAllUrlPrefix = 'classpath*:';

  /// The loader for locations without wildcards and for prefixes this
  /// resolver does not expand.
  final ResourceLoader resourceLoader;

  /// The matcher that compares paths with the pattern.
  final PathMatcher pathMatcher;

  @override
  Resource getResource(String location) => resourceLoader.getResource(location);

  @override
  List<Resource> getResources(String locationPattern) {
    if (locationPattern.startsWith(classpathAllUrlPrefix)) {
      final path = locationPattern.substring(classpathAllUrlPrefix.length);
      if (!pathMatcher.isPattern(path)) {
        final normalized = _classpathDirectory(path);
        if (normalized == null) {
          return const []; // climbs above the roots: nothing there
        }
        return [
          for (final root in _roots())
            if (root.resolve(normalized) case final resource
                when resource.exists())
              resource,
        ];
      }
      final pattern = _classpathPattern(path);
      if (pattern == null) {
        return const []; // climbs above the roots: nothing there
      }
      return [for (final root in _roots()) ..._matches(root, pattern)];
    }
    final isFile = locationPattern.startsWith(ResourceLoader.filePrefix);
    // Plain locations are classpath locations, as in DefaultResourceLoader.
    final isClasspath =
        locationPattern.startsWith(ClasspathResources.prefix) ||
        !RegExp('^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(locationPattern);
    // As in Spring, the wildcards are looked for in the location as
    // written: `file:mail/%2A.txt` is the file named `*.txt`, no pattern.
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
      final pattern = _classpathPattern(path);
      if (pattern == null) {
        return const []; // climbs above the roots: nothing there
      }
      for (final root in _roots()) {
        if (root.hasDirectory(pattern.base)) {
          return _matches(root, pattern);
        }
      }
      return const [];
    }
    // Walk the directory before the first wildcard segment and match the
    // rest, cleaned as Spring's StringUtils.cleanPath cleans it, against
    // paths relative to it. As in Spring, only that directory is
    // percent-decoded (its URL's file): `file:my%20dir/*.txt` walks
    // `my dir/`, while the rest is matched as written.
    final raw = _filePath(locationPattern);
    final root = _rootDirectory(raw);
    final directory = FileSystemResource(_decoded(root)).path;
    final pattern = _subPattern(raw.substring(root.length));
    if (pattern == null || !FileAccess.isDirectory(directory)) {
      return const [];
    }
    final prefix = directory.endsWith('/') ? directory : '$directory/';
    return [
      for (final relative in _walk(directory, pattern))
        FileSystemResource('$prefix$relative'),
    ];
  }

  // The path of a `file:` [url] as FileSystemResource.fromFileUrl reads it
  // (an empty or `localhost` host dropped), `\` read as `/` as Spring's
  // cleanPath reads it ([_slashes]; `file:C:\config\*.properties`), not
  // cleaned and not percent-decoded yet ([_decoded]).
  static String _filePath(String url) {
    var rest = url.substring(ResourceLoader.filePrefix.length);
    if (rest.startsWith('///')) {
      rest = rest.substring(2);
    } else if (rest.startsWith('//localhost/')) {
      rest = rest.substring('//localhost'.length);
    }
    return _slashes(rest);
  }

  // [path] percent-decoded, as the file of a `file:` URL is; a `%` that
  // starts no valid escape is a literal `%` (`file:100%.txt`).
  static String _decoded(String path) {
    if (!path.contains('%')) {
      return path;
    }
    try {
      return Uri.decodeComponent(path);
    } on ArgumentError {
      return path;
    }
  }

  // [path] with `\` read as `/`, in the two steps of Spring's
  // StringUtils.cleanPath: each `\\` (two backslashes) becomes one `/`,
  // then each `\` left does. So `*\\..\\*.txt` is `*/../*.txt`, whose
  // `..` removes the `*` directory (`*.txt`), not `*//..//*.txt`, whose
  // `..` removes an empty segment.
  static String _slashes(String path) => path.contains(r'\')
      ? path.replaceAll(r'\\', '/').replaceAll(r'\', '/')
      : path;

  // A classpath pattern split as Spring's determineRootDir splits it: the
  // directory before the first segment with wildcards ([_classpathDirectory])
  // and the rest, cleaned as Spring 7 cleans it ([_subPattern]):
  // `classpath:mail\*.txt` is `classpath:mail/*.txt` and
  // `classpath:mail/{n:\w+}.txt` matches nothing, as in Spring. `null` when
  // a `..` climbs above the roots or above that directory: nothing there.
  _ClasspathPattern? _classpathPattern(String path) {
    final directory = _rootDirectory(path);
    final base = _classpathDirectory(directory);
    final rest = _subPattern(path.substring(directory.length));
    return base == null || rest == null ? null : (base: base, rest: rest);
  }

  // A classpath directory as the roots' paths are written: no leading
  // slash, `\` read as `/`, `.`, `..` and empty segments resolved
  // (`./emb/`, `sub/../emb/` and `emb//` are `emb/`), a trailing slash
  // kept, `''` for the root itself. `null` when `..` climbs above the
  // roots.
  static String? _classpathDirectory(String directory) =>
      switch (ClasspathResources.normalize(directory)) {
        null => null,
        '.' || '' => '',
        final cleaned when directory.endsWith('/') && !cleaned.endsWith('/') =>
          '$cleaned/',
        final cleaned => cleaned,
      };

  // The part of a pattern after its root directory, cleaned as Spring 7
  // cleans it (`StringUtils.cleanPath(subPattern)` in
  // doFindPathMatchingFileResources): `\` read as `/`, `.` segments
  // dropped, a `..` removing the segment before it (`*/../*.txt` is
  // `*.txt`). `null` when a `..` is left over: it climbs above the root
  // directory, where no walked path is.
  static String? _subPattern(String pattern) {
    final cleaned = _cleanPath(pattern);
    return cleaned == '..' || cleaned.startsWith('../') ? null : cleaned;
  }

  // [path] cleaned like Spring's StringUtils.cleanPath: `\` read as `/`
  // ([_slashes]: `\\` first), `.` segments dropped and a `..` removing
  // the segment before it (`**/./a/../*.txt` is `**/*.txt`); leading `..`
  // segments, empty segments and a trailing `/` kept. As in Spring, text
  // up to a first `:` with no `/` before it is a prefix left as it is.
  static String _cleanPath(String path) {
    if (path.isEmpty) {
      return path;
    }
    final normalized = _slashes(path);
    if (!normalized.contains('.')) {
      return normalized;
    }
    var rest = normalized;
    var prefix = '';
    final colon = rest.indexOf(':');
    if (colon != -1 && !rest.substring(0, colon).contains('/')) {
      prefix = rest.substring(0, colon + 1);
      rest = rest.substring(colon + 1);
    }
    if (rest.startsWith('/')) {
      prefix = '$prefix/';
      rest = rest.substring(1);
    }
    final segments = rest.isEmpty ? const <String>[] : rest.split('/');
    final kept = <String>[];
    var tops = 0;
    for (final segment in segments.reversed) {
      if (segment == '.') {
        continue;
      }
      if (segment == '..') {
        tops++;
      } else if (tops > 0) {
        tops--;
      } else {
        kept.add(segment);
      }
    }
    if (kept.length == segments.length) {
      return normalized;
    }
    final result = [for (var i = 0; i < tops; i++) '..', ...kept.reversed];
    if (result.length == 1 && result.single.isEmpty && !prefix.endsWith('/')) {
      result.insert(0, '.');
    }
    return '$prefix${result.join('/')}';
  }

  // The classpath roots, in lookup order.
  List<_ClasspathRoot> _roots() => [
    for (final directory in ClasspathResources.directories)
      _DirectoryRoot(directory),
    _EmbeddedRoot(),
  ];

  // The resources of [root] matching [pattern], sorted by path.
  List<Resource> _matches(_ClasspathRoot root, _ClasspathPattern pattern) => [
    for (final path in root.paths(this, pattern.base, pattern.rest))
      root.resolve(path),
  ];

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

// A classpath pattern: the directory before the first segment with
// wildcards (`mail/`, `''` for the root) and the rest, each cleaned.
typedef _ClasspathPattern = ({String base, String rest});

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
  static const String _directory = ClasspathResources.directory;

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
