import 'dart:convert';

import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/io/properties_parser.dart';

/// A reader for one config file format: it turns the text of a file into
/// property sources, one per document in the file.
///
/// The config data loader picks a loader by file extension. `.properties`
/// ([PropertiesPropertySourceLoader]) and `.yml` / `.yaml`
/// (`YamlPropertySourceLoader`) are built in, which covers almost every
/// application. Write one only for another format, such as JSON or TOML
/// config files, and pass it to a `ConfigDataEnvironment` you run
/// yourself; `SpringApplication` always uses the two built-in loaders.
///
/// Unlike Spring Boot, a loader gets the file's content as a string, not a
/// `Resource`, because some resources can only be read asynchronously; the
/// file is decoded with [encoding] first.
///
/// ```dart
/// // `application.json` files next to the YAML ones.
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
  /// Lets subclasses be `const`.
  const PropertySourceLoader();

  /// The file extensions this loader reads, without the dot (`json`).
  /// When several loaders claim one, the first in the list wins.
  List<String> get fileExtensions;

  /// The character encoding the files are decoded with before [load];
  /// UTF-8 unless overridden.
  Encoding get encoding => utf8;

  /// Parses [content], the text of one file, into one property source per
  /// document, in file order, skipping empty documents. Keys must be
  /// flat (`server.port`), as in a `.properties` file.
  ///
  /// [name] names the file in the sources (and so in error messages); a
  /// file with several documents should make it unique per document, as
  /// in `'$name (document #1)'`. Throw a [FormatException] for invalid
  /// content: the config data loader reports it with the location.
  List<AbstractPropertySource<Object>> load(String name, String content);
}

/// The reader for `.properties` config files, used for
/// `application.properties` and its profile variants.
///
/// A file can hold several documents, separated by a line `#---` or
/// `!---`; each becomes its own property source, so a later document can
/// be limited to a profile. The config data loader uses it by default, so
/// applications only write the files. Create one only to read
/// `.properties` files in another encoding.
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
  /// Creates a loader that decodes files with [encoding], UTF-8 unless
  /// given.
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
