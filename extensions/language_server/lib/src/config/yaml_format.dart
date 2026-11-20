import 'package:dart_spring_language_server/src/config/config_format.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/config/yaml_entries.dart';
import 'package:dart_spring_language_server/src/config/yaml_keys.dart';
import 'package:dart_spring_language_server/src/index/package_layout.dart';
import 'package:dart_spring_language_server/src/properties/property_entry.dart';

final _typedKey = RegExp(r'^[A-Za-z0-9_.\-\[\]*"]*$');

/// YAML config files, read two ways behind this one format.
///
/// For the index, as the framework's loader reads them
/// ([parseYamlProperties], package:yaml): flattened keys with list indexes,
/// merge keys applied, each document under its profile; a document that
/// does not parse gives no entries. For editing, line by line from the
/// indentation ([scanYamlKeys]): an open document is often invalid YAML
/// while it is typed, and the editor needs the place of every segment of a
/// key, which the parser does not give.
final class YamlFormat implements ConfigFormat {
  /// The format.
  const YamlFormat();

  @override
  bool accepts(String path) => path.endsWith('.yml') || path.endsWith('.yaml');

  @override
  bool recognises(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    return accepts(name) &&
        (PackageLayout.inResources(path) || name.startsWith('application'));
  }

  @override
  List<PropertyEntry> entries(String path, String text) =>
      parseYamlProperties(path, text);

  @override
  List<ConfigKey> keys(String path, String text) => scanYamlKeys(text);

  @override
  String content(String line) => stripYamlComment(line);

  @override
  bool inComment(String before) =>
      stripYamlComment(before).length != before.length;

  @override
  ValueSplit? valueSplit(String before) {
    var content = before;
    var offset = 0;
    while (true) {
      final trimmed = content.trimLeft();
      if (trimmed != '-' && !trimmed.startsWith('- ')) {
        break;
      }
      final skip = content.length - trimmed.length + (trimmed == '-' ? 1 : 2);
      offset += skip;
      content = content.substring(skip);
    }
    final body = content.trimLeft();
    offset += content.length - body.length;
    var from = 0;
    if (body.isNotEmpty && (body[0] == '"' || body[0] == "'")) {
      final close = body.indexOf(body[0], 1);
      if (close < 0) {
        return null;
      }
      from = close + 1;
    }
    for (var i = from; i < body.length; i++) {
      if (body[i] == ':' && (i + 1 == body.length || body[i + 1] == ' ')) {
        final rest = body.substring(i + 1);
        final value = rest.trimLeft();
        return (
          key: body.substring(0, i).trim(),
          value: value,
          start: offset + i + 1 + (rest.length - value.length),
        );
      }
      if (body[i] == ' ' && i + 1 < body.length && body[i + 1] == '#') {
        return null;
      }
    }
    return null;
  }

  @override
  List<String> keyPath(List<String> lines, int line, String keyText) => [
    ...yamlParentSegments(lines, line),
    for (final part in dottedParts(
      keyText.replaceAll(RegExp('^["\']|["\']\$'), ''),
      0,
    ))
      part.$1,
  ];

  @override
  KeyTyping? keyTyping(List<String> lines, int line, String before) {
    var content = before;
    var offset = 0;
    while (content.trimLeft() == '-' || content.trimLeft().startsWith('- ')) {
      final trimmed = content.trimLeft();
      final skip = content.length - trimmed.length + (trimmed == '-' ? 1 : 2);
      offset += skip;
      content = content.substring(skip);
    }
    final trimmed = content.trimLeft();
    if (!_typedKey.hasMatch(trimmed)) {
      return null;
    }
    final dots = trimmed.lastIndexOf('.');
    return (
      parents: [
        ...yamlParentSegments(lines, line),
        if (dots >= 0)
          for (final part in dottedParts(trimmed.substring(0, dots), 0))
            part.$1,
      ],
      partial: dots < 0 ? trimmed : trimmed.substring(dots + 1),
      start:
          offset + content.length - trimmed.length + (dots < 0 ? 0 : dots + 1),
    );
  }

  @override
  String keyInsert(
    String name, {
    required bool group,
    required int indent,
    required bool hasColon,
  }) => hasColon
      ? name
      : group
      ? nestedInsert(name, indent)
      : '$name: ';

  @override
  String nestedInsert(String name, int indent) =>
      '$name:\n${' ' * (indent + 2)}';
}
