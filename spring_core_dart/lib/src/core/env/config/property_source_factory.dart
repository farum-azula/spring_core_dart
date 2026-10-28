import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_core_dart/src/core/env/env_exceptions.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/io/path_matcher.dart';
import 'package:spring_core_dart/src/core/io/resource.dart';
import 'package:spring_core_dart/src/core/io/resource_loader.dart';
import 'package:spring_core_dart/src/core/io/resource_pattern_resolver.dart';
import 'package:spring_core_dart/src/core/io/resource_property_source.dart';
import 'package:spring_core_dart/src/core/io/url_resource.dart';

/// Turns a file named in `@PropertySource` into a property source; write
/// one to let `@PropertySource` read a format other than `.properties`.
///
/// `@PropertySource(['classpath:extra.properties'])` adds one file's
/// properties to the environment from a `@Configuration` class. As in
/// Spring, it reads `.properties` files unless the annotation's `factory`
/// names a class implementing this interface. The usual reason to write
/// one is YAML. The factory class needs a constructor without arguments,
/// so the generated code can create it. Most applications need neither:
/// `application.yml` and `spring.config.import` already read YAML.
///
/// ```dart
/// // Lets `@PropertySource` read YAML: all documents merged into one.
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
  /// Reads [resource] synchronously, decoded with its encoding, and
  /// returns its properties as one source. Name the source [name] when it
  /// is given (the annotation's `name`), otherwise after the resource.
  AbstractPropertySource<Object> createPropertySource(
    String? name,
    EncodedResource resource,
  );
}

/// The factory `@PropertySource` uses when none is named: it reads the file
/// as `.properties`.
///
/// It creates a `ResourcePropertySource` named after the resource unless a
/// name is given. Applications do not use it directly; it is the default
/// value of [PropertySourceProcessor.processPropertySource]'s `factory`.
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
  /// Creates the factory. It holds no state, so a `const` one can be
  /// shared.
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

/// The startup error for a file named in `@PropertySource` that does not
/// exist.
///
/// Applications meet it as a failed start. Set `ignoreResourceNotFound:
/// true` on the annotation when the file is allowed to be missing, such as
/// a local override file.
///
/// ```dart
/// try {
///   processor.processPropertySource(['file:missing.properties']);
/// } on PropertySourceNotFoundException catch (error) {
///   log.error(error.location); // file:missing.properties
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
  /// Creates the exception for [location], which was looked up as the
  /// resource described by [description].
  PropertySourceNotFoundException(this.location, this.description);

  /// The location as declared, before `${...}` placeholders were resolved.
  final String location;

  /// The resource that was looked for, with placeholders resolved.
  final String description;

  @override
  String toString() =>
      'PropertySourceNotFoundException: $description '
      '(location "$location") does not exist';
}

/// The code that reads the files of `@PropertySource` annotations into an
/// environment.
///
/// The application context runs it for every `@PropertySource`, so
/// applications just write the annotation. Use it directly to add
/// property files to an environment by hand, with the same rules:
/// `${...}` in locations, patterns such as `file:conf/*.properties`,
/// missing files allowed or not.
///
/// The first source it adds goes last in the environment (lowest
/// precedence); every later one goes just above the previous one, so the
/// last location declared wins.
///
/// ```dart
/// // A tool that reads an optional local override on top of a base file.
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
  /// Creates a processor that adds sources to [environment] and finds the
  /// files with [resourceLoader].
  PropertySourceProcessor(this.environment, this.resourceLoader);

  /// The environment the sources are added to; placeholders in locations
  /// are resolved against it.
  final ConfigurableEnvironment environment;

  /// Finds the resource for each location once its placeholders are
  /// resolved.
  final ResourceLoader resourceLoader;

  // Names of the sources this processor added, oldest first; the next
  // source goes right above the last one.
  final _added = <String>[];

  /// Reads every file in [locations] into the environment, with the
  /// arguments of `@PropertySource`. `${...}` in a location is resolved
  /// against the environment first.
  ///
  /// A pattern (`file:conf/*.properties`, `classpath*:`) adds every match,
  /// and no match is fine. With [ignoreResourceNotFound], missing files and
  /// unresolvable placeholders are skipped; otherwise they throw
  /// `PropertySourceNotFoundException` or `PlaceholderResolutionException`.
  /// [factory] reads each file (`.properties` unless given). [name] gives
  /// all sources of this call one name, so they are merged into one
  /// composite source. [encoding] is the name of the charset the files are
  /// read in (such as `ISO-8859-1`; UTF-8 when `null`); an unknown name
  /// throws [ArgumentError].
  ///
  /// Resources that can only be read asynchronously (Flutter assets, URLs)
  /// must be [preload]ed first; otherwise they throw a [StateError].
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
      if (!resource.exists() || _missing.contains(resource.description)) {
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

  /// Reads ahead the resources of [locations] that can only be read
  /// asynchronously (Flutter assets behind a `ProtocolResolver`, URLs), so
  /// that a later [processPropertySource] can use them synchronously.
  ///
  /// Locations whose placeholders cannot be resolved yet, and missing
  /// resources, are skipped here; [processPropertySource] reports them.
  /// `ConfigurableApplicationContext.refreshAsync` calls it for every
  /// `@PropertySource`, which is why such files need an asynchronous
  /// start.
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
          _missing.contains(key) ||
          !resource.exists()) {
        continue;
      }
      // A URL is asked with a HEAD request first (Spring's
      // UrlResource.exists()), so a 404 is a missing resource.
      if (resource is UrlResource && !await resource.existsAsync()) {
        _missing.add(key);
        continue;
      }
      _preloaded[key] = await resource.readAsBytes();
    }
  }

  // Content of async-only resources read by [preload], by description.
  final _preloaded = <String, Uint8List>{};

  // Descriptions of URL resources [preload] found missing.
  final _missing = <String>{};

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
        final composite =
            (existing is CompositePropertySource
                  ? existing
                  : (CompositePropertySource(name)
                      ..addPropertySource(existing)))
              ..addFirstPropertySource(source);
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
