import 'package:spring_core_dart/src/core/io/classpath_resources.dart';
import 'package:spring_core_dart/src/core/io/file_access_stub.dart'
    if (dart.library.io) 'package:spring_core_dart/src/core/io/file_access_io.dart';
import 'package:spring_core_dart/src/core/io/file_system_resource.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/url_resource.dart';

/// Loads resources by location, like Spring's `ResourceLoader`.
///
/// ```dart
/// final ResourceLoader loader = DefaultResourceLoader();
/// final resource = loader.getResource('file:config/app.properties');
/// ```
///
/// Spring (Java):
/// ```java
/// ResourceLoader loader = new DefaultResourceLoader();
/// Resource resource = loader.getResource("file:config/app.properties");
/// ```
///
/// `classpath:` reads `lib/resources/` (see [ClasspathResources]); register a
/// [ProtocolResolver] for other
/// sources (e.g. Flutter assets).
abstract interface class ResourceLoader {
  /// Prefix for file system locations.
  static const filePrefix = 'file:';

  /// Returns a handle for [location]; it may not exist.
  ///
  /// Never returns `null`; check [Resource.exists].
  Resource getResource(String location);
}

/// Resolves custom location protocols, like Spring's `ProtocolResolver`.
///
/// ```dart
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
  /// A resource for [location], or `null` if this resolver does not handle
  /// it.
  Resource? resolve(String location, ResourceLoader resourceLoader);
}

/// A [ProtocolResolver] from a function.
///
/// ```dart
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
  /// Wraps a resolve function; it returns `null` for locations it does
  /// not handle.
  const FunctionProtocolResolver(this._resolve);

  final Resource? Function(String location, ResourceLoader loader) _resolve;

  @override
  Resource? resolve(String location, ResourceLoader resourceLoader) =>
      _resolve(location, resourceLoader);
}

/// Serves `prefix:path` locations from an in-memory map; handy for tests
/// and for content embedded in the app.
///
/// Paths are normalized (`./`, `..`, leading `/`), so `memory:config/a`
/// and `memory:/config/./a` are the same file. Unknown paths resolve to a
/// resource that does not exist.
///
/// ```dart
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
  /// Serves [files] (path → content, copied) under [prefix].
  InMemoryProtocolResolver(this.prefix, Map<String, String> files)
    : _files = Map.of(files);

  /// Protocol prefix including the colon, e.g. `memory:`.
  final String prefix;
  final Map<String, String> _files;

  /// Adds or replaces [path].
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

/// Default [ResourceLoader], like Spring's `DefaultResourceLoader`.
///
/// Order: registered [ProtocolResolver]s, then `classpath:` (the files of
/// `lib/resources/`, see [ClasspathResources]), then `file:` as file system
/// resources (percent-decoded, see [FileSystemResource.fromFileUrl]), then
/// `package:` URIs as the package's files (through the package config of
/// the running program; not on the web or in AOT executables). Plain paths
/// (`app.properties`, `/config/x.txt`) are classpath resources too, like
/// Spring's `getResourceByPath`. `http:` / `https:` locations are
/// [UrlResource]s. Other `scheme:` locations resolve to a resource that
/// does not exist.
///
/// Platforms with their own asset system plug in with a
/// [ProtocolResolver], which comes first: a Flutter app can resolve
/// `package:my_app/config/app.properties` (or an `asset:` scheme) to an
/// async-only resource over its asset bundle, which `ConfigDataEnvironment`
/// and `@PropertySource` then read asynchronously.
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
  /// Creates a loader that tries [protocolResolvers] first, in order.
  DefaultResourceLoader({
    Iterable<ProtocolResolver> protocolResolvers = const [],
  }) : _resolvers = [...protocolResolvers];

  final List<ProtocolResolver> _resolvers;

  /// Resolvers tried before the built-in rules.
  List<ProtocolResolver> get protocolResolvers => List.unmodifiable(_resolvers);

  /// Registers [resolver]; later ones are tried after earlier ones.
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
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]+:').hasMatch(location)) {
      return DescriptiveResource('resource [$location] (unsupported protocol)');
    }
    // A plain path is a classpath resource, like Spring's getResourceByPath
    // (a leading `/` is ignored).
    return ClasspathResources.resolve(location);
  }

  /// Prefix of a Dart package URI (`package:my_app/config/app.yml`).
  static const packagePrefix = 'package:';
}
