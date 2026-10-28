import 'package:spring_core_dart/src/core/io/classpath_resources.dart';
import 'package:spring_core_dart/src/core/io/file_access_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/io/file_access_io.dart';
import 'package:spring_core_dart/src/core/io/file_system_resource.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/url_resource.dart';

/// Turns a location string such as `classpath:mail.txt`,
/// `file:./data.csv` or `https://...` into a [Resource] to read.
///
/// It is the one place that knows what the prefixes mean, so code can take
/// a location from configuration and read it without caring where it
/// points. The application context is the resource loader beans get: a
/// constructor parameter of type `ResourceLoader` receives it
/// (`ResourceLoaderAware` works too). For a fixed location,
/// `@Value('classpath:...') Resource` is simpler. `classpath:` reads
/// `lib/resources/` (see [ClasspathResources]); a [ProtocolResolver] adds
/// other prefixes, such as Flutter assets.
///
/// ```dart
/// @Service()
/// class Imports {
///   Imports(this.resources, @Value(r'${shop.import.file}') this.location);
///
///   final ResourceLoader resources; // the application context
///   final String location; // `file:./import.csv` or `classpath:demo.csv`
///
///   Future<String> read() => resources.getResource(location).readAsString();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @Service
/// class Imports {
///   private final ResourceLoader resources;
///   private final String location;
///
///   Imports(ResourceLoader resources,
///       @Value("${shop.import.file}") String location) {
///     this.resources = resources;
///     this.location = location;
///   }
///
///   String read() throws IOException {
///     return resources.getResource(location)
///         .getContentAsString(StandardCharsets.UTF_8);
///   }
/// }
/// ```
abstract interface class ResourceLoader {
  /// The prefix of file system locations: `file:`.
  static const filePrefix = 'file:';

  /// The resource at [location]. Nothing is read yet, and the resource may
  /// not exist: check [Resource.exists] before reading when it may be
  /// missing. Never returns `null`; an unknown prefix gives a resource
  /// that does not exist.
  Resource getResource(String location);
}

/// A plug-in that teaches a resource loader a location prefix of its own,
/// such as `asset:` or `db:`.
///
/// Resolvers are asked before the built-in prefixes, in the order they
/// were added; each returns a resource for the locations it handles and
/// `null` for the others. Register one on the application context
/// (`addProtocolResolver`) before it starts, and every `@Value` resource,
/// `@PropertySource` file and config import can use the prefix. The
/// Flutter starter registers one for assets; applications write one only
/// for their own storage.
///
/// ```dart
/// // `asset:config/app.yml` read from the app's asset bundle.
/// class AssetProtocolResolver implements ProtocolResolver {
///   @override
///   Resource? resolve(String location, ResourceLoader resourceLoader) =>
///       location.startsWith('asset:')
///           ? AssetResource(location.substring(6))
///           : null;
/// }
///
/// final loader = DefaultResourceLoader(
///   protocolResolvers: [AssetProtocolResolver()],
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// ProtocolResolver assets = (location, loader) ->
///     location.startsWith("asset:")
///         ? new AssetResource(location.substring(6))
///         : null;
/// var loader = new DefaultResourceLoader();
/// loader.addProtocolResolver(assets);
/// ```
abstract interface class ProtocolResolver {
  /// The resource for [location], or `null` when this resolver does not
  /// handle it, so the next resolver (or the built-in rules) is tried.
  /// [resourceLoader] is the loader asking, for resolvers that delegate.
  Resource? resolve(String location, ResourceLoader resourceLoader);
}

/// A [ProtocolResolver] made from a function, for a resolver too small to
/// deserve a class.
///
/// ```dart
/// // One fixed location served from memory.
/// final loader = DefaultResourceLoader(
///   protocolResolvers: [
///     FunctionProtocolResolver(
///       (location, _) => location == 'inline:greeting'
///           ? ByteArrayResource.fromString('hello=world')
///           : null,
///     ),
///   ],
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// // ProtocolResolver is a functional interface, so a lambda is enough:
/// loader.addProtocolResolver((location, resourceLoader) ->
///     location.equals("inline:greeting")
///         ? new ByteArrayResource("hello=world".getBytes())
///         : null);
/// ```
final class FunctionProtocolResolver implements ProtocolResolver {
  /// Creates a resolver that calls the given function, which returns
  /// `null` for locations it does not handle.
  const FunctionProtocolResolver(this._resolve);

  final Resource? Function(String location, ResourceLoader loader) _resolve;

  @override
  Resource? resolve(String location, ResourceLoader resourceLoader) =>
      _resolve(location, resourceLoader);
}

/// A [ProtocolResolver] that serves `prefix:path` locations from a map of
/// paths to text held in memory.
///
/// It is for tests that need config files or templates without touching
/// the disk, and for content an app builds in code. Paths are normalized
/// (`./`, `..`, a leading `/`), so `memory:config/a` and
/// `memory:/config/./a` are the same file. An unknown path gives a
/// resource that does not exist.
///
/// ```dart
/// // Config files for a test, without files on disk.
/// final loader = DefaultResourceLoader(
///   protocolResolvers: [
///     InMemoryProtocolResolver('memory:', {
///       'config/application.properties': 'app.name=demo',
///     }),
///   ],
/// );
/// final environment = StandardEnvironment();
/// ConfigDataEnvironment(
///   environment,
///   resourceLoader: loader,
///   defaultLocations: const ['optional:memory:config/'],
/// ).processAndApplySync();
/// ```
///
/// Spring has no direct equivalent; tests usually use `ByteArrayResource`,
/// `MockPropertySource` or `@TestPropertySource` instead.
final class InMemoryProtocolResolver implements ProtocolResolver {
  /// Creates a resolver serving [files] (path to content, copied) under
  /// [prefix].
  InMemoryProtocolResolver(this.prefix, Map<String, String> files)
    : _files = Map.of(files);

  /// The prefix it handles, colon included, such as `memory:`.
  final String prefix;
  final Map<String, String> _files;

  /// Adds the file [path] with [content], or replaces its content.
  void put(String path, String content) => _files[path] = content;

  @override
  Resource? resolve(String location, ResourceLoader resourceLoader) {
    if (!location.startsWith(prefix)) {
      return null;
    }
    final path = _normalize(location.substring(prefix.length));
    final content = _files[path];
    final description = 'resource [$prefix$path]';
    return content == null
        ? DescriptiveResource(description)
        : ByteArrayResource.fromString(content, description: description);
  }

  // Reuses FileSystemResource's path cleaning (pure string logic, works on
  // the web too), then drops the leading slash so keys are relative.
  static String _normalize(String path) =>
      FileSystemResource(path).path.replaceFirst(RegExp('^/'), '');
}

/// The [ResourceLoader] used everywhere: it knows `classpath:`, `file:`,
/// `http:`, `https:` and `package:` locations, plus any prefix taught by a
/// [ProtocolResolver].
///
/// The application context uses one unless given another loader, so
/// applications mostly use it through the context. Create one directly to
/// read resources without a context, in a tool or a test. Locations are
/// handled in this order:
///
/// 1. Registered [ProtocolResolver]s, in order.
/// 2. `classpath:`: the files of `lib/resources/` (see
///    [ClasspathResources]).
/// 3. `file:`: a [FileSystemResource], percent-decoded (see
///    [FileSystemResource.fromFileUrl]).
/// 4. `http:` and `https:`: a [UrlResource].
/// 5. `package:`: the package's file, through the package config of the
///    running program; not on the web or in AOT executables.
/// 6. Any other `scheme:`: a resource that does not exist.
/// 7. A plain path (`app.properties`, `/config/x.txt`): a classpath
///    resource, like Spring's `getResourceByPath`.
///
/// Platforms with their own asset system plug in with a
/// [ProtocolResolver], which comes first: a Flutter app can resolve
/// `package:my_app/config/app.properties` (or an `asset:` scheme) to a
/// resource over its asset bundle that is read asynchronously, which
/// `ConfigDataEnvironment` and `@PropertySource` support.
///
/// ```dart
/// final loader = DefaultResourceLoader()
///   ..addProtocolResolver(InMemoryProtocolResolver('memory:', {}));
/// loader.getResource('config/app.properties'); // lib/resources/config/...
/// loader.getResource('file:///etc/app.properties'); // FileSystemResource
/// loader.getResource('https://example.com/x'); // UrlResource
/// loader.getResource('ftp://example.com/x').exists(); // false
/// ```
///
/// Spring (Java):
/// ```java
/// var loader = new DefaultResourceLoader();
/// loader.addProtocolResolver(myResolver);
/// Resource onClasspath = loader.getResource("config/app.properties");
/// Resource file = loader.getResource("file:config/app.properties");
/// ```
class DefaultResourceLoader implements ResourceLoader {
  /// Creates a loader that asks [protocolResolvers] first, in order, before
  /// its built-in rules.
  DefaultResourceLoader({
    Iterable<ProtocolResolver> protocolResolvers = const [],
  }) : _resolvers = [...protocolResolvers];

  final List<ProtocolResolver> _resolvers;

  /// The resolvers asked before the built-in rules, in order, as a
  /// read-only copy.
  List<ProtocolResolver> get protocolResolvers => List.unmodifiable(_resolvers);

  /// Adds [resolver] after the resolvers already registered.
  void addProtocolResolver(ProtocolResolver resolver) =>
      _resolvers.add(resolver);

  @override
  Resource getResource(String location) {
    for (final resolver in _resolvers) {
      final resource = resolver.resolve(location, this);
      if (resource != null) {
        return resource;
      }
    }
    if (location.startsWith(ClasspathResources.prefix)) {
      return ClasspathResources.resolve(location);
    }
    if (location.startsWith(ResourceLoader.filePrefix)) {
      return FileSystemResource.fromFileUrl(location);
    }
    if (location.startsWith('http:') || location.startsWith('https:')) {
      return UrlResource(Uri.parse(location));
    }
    if (location.startsWith(packagePrefix)) {
      final path = FileAccess.resolvePackageUri(location);
      return path == null
          ? DescriptiveResource('resource [$location] (cannot be resolved)')
          : FileSystemResource(path);
    }
    // Another `scheme:` prefix (at least two letters, so a Windows drive
    // like `C:\` is still a plain path).
    if (RegExp('^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(location)) {
      return DescriptiveResource('resource [$location] (unsupported protocol)');
    }
    // A plain path is a classpath resource, like Spring's getResourceByPath
    // (a leading `/` is ignored).
    return ClasspathResources.resolve(location);
  }

  /// The prefix of a Dart package URI, `package:`, as in
  /// `package:my_app/config/app.yml`.
  static const packagePrefix = 'package:';
}
