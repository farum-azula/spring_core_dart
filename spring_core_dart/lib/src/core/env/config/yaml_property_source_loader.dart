import 'package:spring_core_dart/src/core/env/config/property_source_loader.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:yaml/yaml.dart';

/// `.yml` / `.yaml` files, like Spring Boot's `YamlPropertySourceLoader`;
/// `ConfigDataEnvironment` uses it by default.
///
/// Every YAML document (documents are separated by `---`) becomes one
/// property source, flattened like Spring's `YamlProcessor`:
///
/// - nested maps become dotted keys: `server: {port: 8080}` is
///   `server.port`;
/// - list items are indexed: `hosts[0]`, `servers[1].name`;
/// - `~`, `null` and empty values are `''`, and so are empty lists and
///   maps (`app.tags: []`);
/// - keys that are not strings are put in brackets: `1: a` is `[1]`, and
///   `"[a.b]"` keys keep their dots (`app.map[a.b]`);
/// - scalars keep their YAML type (`8080` is an `int`, `true` a `bool`),
///   strings (including `|` and `>` block scalars) stay as written;
/// - merge keys (`<<: *defaults`) copy the entries of the referenced
///   mappings that the mapping does not define itself;
/// - a document that is just a scalar is the property `document`;
///   empty documents are skipped.
///
/// Duplicate keys are an error, as in Spring Boot.
///
/// ```yaml
/// # application.yml
/// spring:
///   profiles:
///     active: dev
/// app:
///   hosts: [a.example, b.example]
/// ---
/// spring.config.activate.on-profile: dev
/// app.debug: true
/// ```
///
/// ```dart
/// final sources = const YamlPropertySourceLoader().load(
///   'application.yml',
///   'app:\n  hosts: [a, b]\n',
/// );
/// sources.single.getProperty('app.hosts[1]'); // 'b'
/// ```
///
/// Spring (Java):
/// ```java
/// List<PropertySource<?>> sources = new YamlPropertySourceLoader()
///     .load("application.yml", new ClassPathResource("application.yml"));
/// ```
///
/// Differences from Spring Boot: YAML 1.2 (`package:yaml`) instead of
/// SnakeYAML's YAML 1.1, so `on`, `off`, `yes` and `no` stay strings
/// (converting them to `bool` or an enum still works) and `0777` is the
/// number 777.
final class YamlPropertySourceLoader extends PropertySourceLoader {
  /// Creates the loader (stateless; use `const`).
  const YamlPropertySourceLoader();

  @override
  List<String> get fileExtensions => const ['yml', 'yaml'];

  /// Parses [content]; throws a [FormatException] (a `YamlException` with
  /// the line and column) for invalid YAML.
  @override
  List<AbstractPropertySource<Object>> load(String name, String content) {
    final documents = <Map<String, Object>>[
      for (final document in loadYamlDocuments(content))
        if (_plain(document.contents) case final value? when value != '')
          flatten(value),
    ];
    return [
      for (var i = 0; i < documents.length; i++)
        MapPropertySource(
          documents.length == 1 ? name : '$name (document #$i)',
          Map.unmodifiable(documents[i]),
        ),
    ];
  }

  /// Flattens one parsed YAML document (maps, lists, scalars) into
  /// property keys and values, as described on the class.
  ///
  /// ```dart
  /// YamlPropertySourceLoader.flatten({
  ///   'app': {'hosts': ['a', 'b'], 'tags': []},
  /// }); // {app.hosts[0]: a, app.hosts[1]: b, app.tags: ''}
  /// ```
  static Map<String, Object> flatten(Object document) {
    final result = <String, Object>{};
    if (document is Map) {
      _flatten(result, _stringKeys(document), null);
    } else {
      result['document'] = document;
    }
    return result;
  }

  static Map<String, Object?> _stringKeys(Map<Object?, Object?> map) => {
    for (final MapEntry(:key, :value) in map.entries)
      key is String ? key : '[$key]': value,
  };

  // Spring's YamlProcessor.buildFlattenedMap with Spring Boot's settings
  // (empty maps included as '', null as '').
  static void _flatten(
    Map<String, Object> result,
    Map<String, Object?> source,
    String? path,
  ) {
    if (path != null && source.isEmpty) {
      result[path] = '';
      return;
    }
    source.forEach((key, value) {
      final name = path == null || path.isEmpty
          ? key
          : key.startsWith('[')
          ? '$path$key'
          : '$path.$key';
      switch (value) {
        case Map():
          _flatten(result, _stringKeys(value), name);
        case List() when value.isEmpty:
          result[name] = '';
        case List():
          for (var i = 0; i < value.length; i++) {
            _flatten(result, {'[$i]': value[i]}, name);
          }
        case null:
          result[name] = '';
        default:
          result[name] = value;
      }
    });
  }

  // The plain value of [node]: maps (with merge keys applied), lists and
  // scalar values; `null` for an empty document.
  static Object? _plain(YamlNode node) => switch (node) {
    YamlMap() => _map(node),
    YamlList() => [for (final item in node.nodes) _plain(item)],
    _ => node.value,
  };

  static Map<Object?, Object?> _map(YamlMap node) {
    final result = <Object?, Object?>{};
    final merged = <Object?, Object?>{};
    for (final MapEntry(:key, :value) in node.nodes.entries) {
      final keyNode = key is YamlNode ? key : null;
      final keyValue = keyNode?.value ?? key;
      if (keyValue == '<<' &&
          keyNode is YamlScalar &&
          keyNode.style == ScalarStyle.PLAIN) {
        // Earlier mappings in a merge list win over later ones; keys of
        // the mapping itself win over all of them.
        final sources = value is YamlList ? value.nodes : [value];
        for (final source in sources) {
          if (source is! YamlMap) {
            throw FormatException(
              'Expected a mapping or a list of mappings for merging',
              source.span.text,
            );
          }
          for (final entry in _map(source).entries) {
            merged.putIfAbsent(entry.key, () => entry.value);
          }
        }
        continue;
      }
      result[keyValue] = _plain(value);
    }
    for (final entry in merged.entries) {
      result.putIfAbsent(entry.key, () => entry.value);
    }
    return result;
  }
}
