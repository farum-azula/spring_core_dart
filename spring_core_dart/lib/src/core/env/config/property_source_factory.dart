import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_core_dart/src/core/env/env_exceptions.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/path_matcher.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';
import 'package:spring_core_dart/src/core/io/resource_pattern_resolver.dart';
import 'package:spring_core_dart/src/core/io/resource_property_source.dart';

/// Creates a property source from a resource, like Spring's
/// `PropertySourceFactory` used by `@PropertySource(factory: ...)`.
///
/// The factory type needs a no-argument constructor so generated code can
/// instantiate it. As in Spring, `@PropertySource` reads `.properties`
/// files unless a factory says otherwise; for YAML, use
/// `YamlPropertySourceLoader` in a factory:
///
/// ```dart
/// class YamlPropertySourceFactory implements PropertySourceFactory {
///   const YamlPropertySourceFactory();
///
///   @override
///   AbstractPropertySource<Object> createPropertySource(
///     String? name,
///     EncodedResource resource,
///   ) => MapPropertySource(name ?? resource.resource.description, {
///     for (final document in const YamlPropertySourceLoader().load(
///       resource.resource.description,
///       resource.readAsStringSync(),
///     ))
///       ...(document as MapPropertySource).source,
///   });
/// }
///
/// @Configuration()
/// @PropertySource(['classpath:app.yml'], factory: YamlPropertySourceFactory)
/// class AppConfig {}
/// ```
///
/// Spring (Java):
/// ```java
/// class YamlPropertySourceFactory implements PropertySourceFactory {
///   @Override
///   public PropertySource<?> createPropertySource(
///       String name, EncodedResource resource) throws IOException {
///     var yaml = new YamlPropertiesFactoryBean();
///     yaml.setResources(resource.getResource());
///     return new PropertiesPropertySource(
///         name != null ? name : resource.getResource().getDescription(),
///         yaml.getObject());
///   }
/// }
///
/// @Configuration
/// @PropertySource(value = "classpath:app.yml",
///     factory = YamlPropertySourceFactory.class)
/// class AppConfig {}
/// ```
abstract interface class PropertySourceFactory {
  /// Reads [resource] synchronously, in its encoding; [name] overrides
  /// the default name.
  AbstractPropertySource<Object> createPropertySource(
    String? name,
    EncodedResource resource,
  );
}

/// `.properties` resources, like Spring's `DefaultPropertySourceFactory`.
///
/// Creates a `ResourcePropertySource` named after the resource unless a
/// name is given.
///
/// ```dart
/// final source = const DefaultPropertySourceFactory().createPropertySource(
///   null,
///   EncodedResource(FileSystemResource('config/app.properties')),
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// PropertySource<?> source = new DefaultPropertySourceFactory()
///     .createPropertySource(null, new EncodedResource(
///         new FileSystemResource("config/app.properties")));
/// ```
final class DefaultPropertySourceFactory implements PropertySourceFactory {
  /// Creates the factory (stateless; use `const`).
  const DefaultPropertySourceFactory();

  @override
  AbstractPropertySource<Object> createPropertySource(
    String? name,
    EncodedResource resource,
  ) => ResourcePropertySource.fromResource(
    resource.resource,
    name: name,
    encoding: resource.encoding ?? utf8,
  );
}

/// A `@PropertySource` location that does not exist.
///
/// Not thrown when `ignoreResourceNotFound` is `true`.
///
/// ```dart
/// try {
///   processor.processPropertySource(['file:missing.properties']);
/// } on PropertySourceNotFoundException catch (error) {
///   print(error.location); // file:missing.properties
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// // Spring throws java.io.FileNotFoundException, wrapped in a
/// // BeanDefinitionStoreException during context refresh:
/// @PropertySource("file:missing.properties")
/// ```
final class PropertySourceNotFoundException implements Exception {
  /// Creates the exception for [location], resolved to the resource
  /// described by [description].
  PropertySourceNotFoundException(this.location, this.description);

  /// The location as declared (before placeholder resolution).
  final String location;

  /// Description of the resource that was looked up.
  final String description;

  @override
  String toString() =>
      'PropertySourceNotFoundException: $description '
      '(location "$location") does not exist';
}

/// Loads `@PropertySource` locations into an environment, like Spring's
/// `PropertySourceProcessor`.
///
/// The first source is added with the lowest precedence; every later one
/// is added just above the previous, so the last declared location wins.
///
/// The application context runs it for every `@PropertySource`; use it
/// directly to add files to an environment by hand.
///
/// ```dart
/// final processor = PropertySourceProcessor(
///   environment,
///   DefaultResourceLoader(),
/// );
/// processor.processPropertySource(
///   [r'file:${config.dir}/app.properties', 'file:local.properties'],
///   ignoreResourceNotFound: true,
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// var processor = new PropertySourceProcessor(
///     environment, new DefaultResourceLoader());
/// processor.processPropertySource(new PropertySourceDescriptor(
///     List.of("file:${config.dir}/app.properties", "file:local.properties"),
///     true, null, DefaultPropertySourceFactory.class, null));
/// ```
class PropertySourceProcessor {
  /// Creates a processor adding sources to [environment], loading
  /// locations with [resourceLoader].
  PropertySourceProcessor(this.environment, this.resourceLoader);

  /// The environment that receives the property sources.
  final ConfigurableEnvironment environment;

  /// Resolves (placeholder-resolved) locations to resources.
  final ResourceLoader resourceLoader;

  // Names of the sources this processor added, oldest first; the next
  // source goes right above the last one.
  final _added = <String>[];

  /// Loads every location in [locations]. `${...}` in locations is
  /// resolved against the environment first.
  ///
  /// With [ignoreResourceNotFound], missing files and unresolvable
  /// placeholders are skipped; otherwise they throw
  /// `PropertySourceNotFoundException` or `PlaceholderResolutionException`.
  /// [factory] creates the source (default: `.properties`); [name] names
  /// all sources of this call, which are then merged into one composite.
  /// [encoding] is the charset name the files are read in (such as
  /// `ISO-8859-1`; UTF-8 when `null`).
  ///
  /// Resources that can only be read asynchronously (Flutter assets) must
  /// be [preload]ed first; otherwise they throw a [StateError].
  void processPropertySource(
    List<String> locations, {
    String? name,
    bool ignoreResourceNotFound = false,
    PropertySourceFactory factory = const DefaultPropertySourceFactory(),
    String? encoding,
  }) {
    final charset = encoding == null ? null : _charset(encoding);
    for (final location in locations) {
      final String resolved;
      try {
        resolved = environment.resolveRequiredPlaceholders(location);
      } on PlaceholderResolutionException {
        if (ignoreResourceNotFound) {
          continue;
        }
        rethrow;
      }
      // A pattern (`file:conf/*.properties`, `classpath*:`) loads every
      // match, none being fine (Spring 6.1's PropertySourceProcessor).
      if (_patterns.isPattern(resolved)) {
        final loader = resourceLoader;
        final resolver = loader is ResourcePatternResolver
            ? loader
            : PathMatchingResourcePatternResolver(resourceLoader: loader);
        for (final resource in resolver.getResources(resolved)) {
          _add(
            factory.createPropertySource(
              name,
              EncodedResource(_readable(resource), encoding: charset),
            ),
          );
        }
        continue;
      }
      final resource = resourceLoader.getResource(resolved);
      if (!resource.exists()) {
        if (ignoreResourceNotFound) {
          continue;
        }
        throw PropertySourceNotFoundException(location, resource.description);
      }
      _add(
        factory.createPropertySource(
          name,
          EncodedResource(_readable(resource), encoding: charset),
        ),
      );
    }
  }

  static final _patterns = AntPathMatcher();

  /// Reads the resources of [locations] that only support asynchronous
  /// reading (such as Flutter assets behind a `ProtocolResolver`), so a
  /// later [processPropertySource] can load them synchronously.
  ///
  /// Locations whose placeholders cannot be resolved yet, and missing
  /// resources, are skipped (processing reports them).
  /// `ConfigurableApplicationContext.refreshAsync` does this for every
  /// `@PropertySource`.
  ///
  /// ```dart
  /// await processor.preload(['asset:config/app.properties']);
  /// processor.processPropertySource(['asset:config/app.properties']);
  /// ```
  Future<void> preload(Iterable<String> locations) async {
    for (final location in locations) {
      final String resolved;
      try {
        resolved = environment.resolveRequiredPlaceholders(location);
      } on PlaceholderResolutionException {
        continue;
      }
      final resource = resourceLoader.getResource(resolved);
      final key = resource.description;
      if (resource.supportsSyncRead ||
          _preloaded.containsKey(key) ||
          !resource.exists()) {
        continue;
      }
      _preloaded[key] = await resource.readAsBytes();
    }
  }

  // Content of async-only resources read by [preload], by description.
  final _preloaded = <String, Uint8List>{};

  // [resource], or its preloaded content when it is async-only.
  Resource _readable(Resource resource) {
    if (resource.supportsSyncRead) {
      return resource;
    }
    final bytes = _preloaded[resource.description];
    if (bytes == null) {
      throw StateError(
        '${resource.description} can only be read asynchronously; refresh '
        'the context with refreshAsync() (or call preload first)',
      );
    }
    return ByteArrayResource(bytes, description: resource.description);
  }

  static Encoding _charset(String name) =>
      Encoding.getByName(name) ??
      (throw ArgumentError.value(name, 'encoding', 'Unsupported encoding'));

  // Like Spring's PropertySourceProcessor.addPropertySource: a name this
  // processor already added is extended (merged, newest first); a source
  // with the same name from elsewhere is replaced.
  void _add(AbstractPropertySource<Object> source) {
    final sources = environment.propertySources;
    final name = source.name;
    if (_added.contains(name)) {
      final existing = sources.get(name);
      if (existing != null) {
        final composite = existing is CompositePropertySource
            ? existing
            : (CompositePropertySource(name)..addPropertySource(existing));
        composite.addFirstPropertySource(source);
        sources.replace(name, composite);
        return;
      }
    }
    final last = _added.lastWhere(
      (added) => added != name && sources.containsSource(added),
      orElse: () => '',
    );
    if (last.isEmpty) {
      sources.addLast(source);
    } else {
      sources.addBefore(last, source);
    }
    _added
      ..remove(name)
      ..add(name);
  }
}
