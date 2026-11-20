import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/config/properties_format.dart';
import 'package:dart_spring_language_server/src/config/yaml_format.dart';
import 'package:dart_spring_language_server/src/properties/property_entry.dart';

/// The part of a line before the cursor that holds a value: the key as
/// typed, the value typed so far and the column where it starts.
typedef ValueSplit = ({String key, String value, int start});

/// The key being typed before the cursor: the segments of the keys around
/// it, the segment typed so far and the column where that starts.
typedef KeyTyping = ({List<String> parents, String partial, int start});

/// A format of config files (`.properties`, YAML): how its entries are
/// read for the index, how an open document is read for editing, and the
/// rules of its lines the editor needs.
///
/// The formats are registered once ([formats]); a new format is a new
/// class and one entry there.
abstract interface class ConfigFormat {
  /// The formats of config files.
  static const formats = <ConfigFormat>[PropertiesFormat(), YamlFormat()];

  /// The format of [path], by its extension; `.properties` for any other.
  static ConfigFormat of(String path) => formats.firstWhere(
    (format) => format.accepts(path),
    orElse: () => formats.first,
  );

  /// Whether [path] is a config file of the application, whose keys are
  /// indexed and whose values are highlighted: any `.properties` file, and
  /// YAML named `application*` or under a `resources/` directory. Not every
  /// YAML: `${{ }}` in a CI workflow is no placeholder.
  static bool isConfigFile(String path) =>
      formats.any((format) => format.recognises(path));

  /// Whether [path] has this format's extension.
  bool accepts(String path);

  /// Whether [path] is a config file in this format.
  bool recognises(String path);

  /// The entries of [text], the content of [path], as the framework reads
  /// them: what the index of properties holds. Never throws.
  List<PropertyEntry> entries(String path, String text);

  /// The keys of [text] with the place of each part, read the tolerant way
  /// an open document needs (the text being typed is often not valid).
  List<ConfigKey> keys(String path, String text);

  /// [line] without its comment, for the highlighting.
  String content(String line);

  /// Whether the cursor after [before] (the line up to it) is in a
  /// comment.
  bool inComment(String before);

  /// The key and the value typed so far when the cursor after [before] is
  /// in a value; `null` when it is in a key.
  ValueSplit? valueSplit(String before);

  /// The whole path of the key written [keyText] at [line] of [lines]:
  /// with the keys that enclose it where the format nests them.
  List<String> keyPath(List<String> lines, int line, String keyText);

  /// The key being typed at [line] of [lines] before the cursor, after
  /// [before]; `null` when the text there is no key.
  KeyTyping? keyTyping(List<String> lines, int line, String before);

  /// The text a proposed key [name] inserts: a [group] gets its nested
  /// lines where the format nests, a leaf its separator; nothing more when
  /// the line [hasColon] already. [indent] is the key's column.
  String keyInsert(
    String name, {
    required bool group,
    required int indent,
    required bool hasColon,
  });

  /// The text a proposed group [name] inserts to go on to its first key
  /// (`mix:` and a new line, or `mix.`).
  String nestedInsert(String name, int indent);
}
