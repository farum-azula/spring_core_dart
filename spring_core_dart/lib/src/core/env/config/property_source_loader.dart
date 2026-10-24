import 'dart:convert';

import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/io/properties_parser.dart';

/// Turns the content of a config file into property sources, like Spring
/// Boot's `PropertySourceLoader`. Selected by file extension; `.properties`
/// ([PropertiesPropertySourceLoader]) and `.yml` / `.yaml`
/// (`YamlPropertySourceLoader`) are built in, add a loader for other
/// formats.
///
/// Unlike Spring Boot, loaders get the file content as a string (resources
/// may be async-only), not a `Resource`; it is decoded with [encoding]
/// (UTF-8 unless the loader overrides it).
///
/// ```dart
/// class JsonPropertySourceLoader extends PropertySourceLoader {
///   const JsonPropertySourceLoader();
///
///   @override
///   List<String> get fileExtensions => const ['json'];
///
///   @override
///   List<AbstractPropertySource<Object>> load(String name, String content) =>
///       [
///         MapPropertySource(
///           name,
///           YamlPropertySourceLoader.flatten(jsonDecode(content) as Object),
///         ),
///       ];
/// }
///
/// ConfigDataEnvironment(
///   environment,
///   loaders: const [
///     PropertiesPropertySourceLoader(),
///     YamlPropertySourceLoader(),
///     JsonPropertySourceLoader(),
///   ],
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// public class JsonPropertySourceLoader implements PropertySourceLoader {
///   @Override
///   public String[] getFileExtensions() {
///     return new String[] {"json"};
///   }
///
///   @Override
///   public List<PropertySource<?>> load(String name, Resource resource) {
///     return List.of(new MapPropertySource(name, flattenJson(resource)));
///   }
/// }
/// // registered in META-INF/spring.factories
/// ```
abstract class PropertySourceLoader {
  /// Const constructor for subclasses.
  const PropertySourceLoader();

  /// Extensions handled by this loader, without the dot.
  List<String> get fileExtensions;

  /// The encoding the files are read in; UTF-8 by default.
  Encoding get encoding => utf8;

  /// One property source per document in [content], in file order. Empty
  /// documents are skipped.
  ///
  /// [name] is the base name for the sources; multi-document files should
  /// make it unique per document (e.g. `'$name (document #1)'`).
  List<AbstractPropertySource<Object>> load(String name, String content);
}

/// `.properties` files, including multi-document files separated by a
/// `#---` or `!---` line, like Spring Boot's
/// `PropertiesPropertySourceLoader`.
///
/// ```dart
/// final sources = const PropertiesPropertySourceLoader().load(
///   'application.properties',
///   'a=1\n#---\nspring.config.activate.on-profile=dev\na=2\n',
/// );
/// sources.length; // 2
///
/// // Files in ISO-8859-1, as Spring Boot reads them:
/// ConfigDataEnvironment(
///   environment,
///   loaders: const [PropertiesPropertySourceLoader(encoding: latin1)],
/// );
/// ```
///
/// Spring Boot always reads `.properties` files as ISO-8859-1; here they
/// are UTF-8 unless [encoding] says otherwise.
///
/// Spring (Java):
/// ```java
/// List<PropertySource<?>> sources = new PropertiesPropertySourceLoader()
///     .load("application.properties",
///         new ClassPathResource("application.properties"));
/// ```
final class PropertiesPropertySourceLoader extends PropertySourceLoader {
  /// Creates the loader reading files in [encoding] (use `const`).
  const PropertiesPropertySourceLoader({this.encoding = utf8});

  @override
  final Encoding encoding;

  // A separator line consists only of `#---` or `!---` (trailing blanks
  // allowed), as in Spring Boot.
  static final _separator = RegExp(r'^[#!]---\s*$', multiLine: true);

  @override
  List<String> get fileExtensions => const ['properties'];

  @override
  List<AbstractPropertySource<Object>> load(String name, String content) {
    final documents = content.split(_separator);
    final sources = <AbstractPropertySource<Object>>[];
    for (var i = 0; i < documents.length; i++) {
      final properties = PropertiesParser.parse(documents[i]);
      if (properties.isEmpty) {
        continue;
      }
      sources.add(
        MapPropertySource(
          documents.length == 1 ? name : '$name (document #$i)',
          properties,
        ),
      );
    }
    return sources;
  }
}
