import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/io/properties_parser.dart';

/// Turns the content of a config file into property sources, like Spring
/// Boot's `PropertySourceLoader`. Selected by file extension; add a loader
/// for `yaml`/`yml` to support YAML files.
///
/// Unlike Spring Boot, loaders get the file content as a string (resources
/// may be async-only), not a `Resource`.
///
/// ```dart
/// class YamlPropertySourceLoader implements PropertySourceLoader {
///   const YamlPropertySourceLoader();
///
///   @override
///   List<String> get fileExtensions => const ['yml', 'yaml'];
///
///   @override
///   List<AbstractPropertySource<Object>> load(String name, String content) =>
///       [MapPropertySource(name, flattenYaml(content))];
/// }
///
/// ConfigDataEnvironment(
///   environment,
///   loaders: const [
///     PropertiesPropertySourceLoader(),
///     YamlPropertySourceLoader(),
///   ],
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// public class MyYamlLoader implements PropertySourceLoader {
///   @Override
///   public String[] getFileExtensions() {
///     return new String[] {"yml", "yaml"};
///   }
///
///   @Override
///   public List<PropertySource<?>> load(String name, Resource resource) {
///     return List.of(new MapPropertySource(name, flattenYaml(resource)));
///   }
/// }
/// // registered in META-INF/spring.factories
/// ```
abstract interface class PropertySourceLoader {
  /// Extensions handled by this loader, without the dot.
  List<String> get fileExtensions;

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
/// ```
///
/// Spring (Java):
/// ```java
/// List<PropertySource<?>> sources = new PropertiesPropertySourceLoader()
///     .load("application.properties",
///         new ClassPathResource("application.properties"));
/// ```
final class PropertiesPropertySourceLoader implements PropertySourceLoader {
  /// Creates the loader (stateless; use `const`).
  const PropertiesPropertySourceLoader();

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
