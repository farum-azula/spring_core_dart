import 'package:dart_spring_language_server/src/config/config_format.dart';
import 'package:dart_spring_language_server/src/config/config_key.dart';
import 'package:dart_spring_language_server/src/symbols/source_range.dart';
import 'package:dart_spring_language_server/src/templates.dart';

/// A config file being edited: its text, its format, its keys (read the
/// tolerant way) and the positions in it.
final class ConfigDocument {
  /// The document [path] with the content [text].
  ConfigDocument(this.path, this.text) : format = ConfigFormat.of(path);

  /// The file's path.
  final String path;

  /// The file's content: the open document's, else the disk's.
  final String text;

  /// The file's format.
  final ConfigFormat format;

  /// The keys of the document, in the order of the text.
  late final List<ConfigKey> keys = format.keys(path, text);

  /// The lines of the document.
  late final List<String> lines = text.split('\n');

  /// The zero-based line and column of [offset].
  (int, int) lineColumn(int offset) {
    var line = 0;
    var start = 0;
    for (var i = 0; i < offset && i < text.length; i++) {
      if (text[i] == '\n') {
        line++;
        start = i + 1;
      }
    }
    return (line, offset - start);
  }

  /// The span of [line] from column [from] to [to].
  SourceRange range(int line, int from, int to) =>
      SourceRange(path, line, from, line, to);

  /// The key whose key part is at ([line], [column]), with the index (in
  /// its segments) of the segment there.
  (ConfigKey, int)? keyAt(int line, int column) {
    for (final key in keys) {
      if (key.line != line || key.spans.isEmpty) {
        continue;
      }
      for (var i = 0; i < key.spans.length; i++) {
        if (column >= key.spans[i].$1 && column <= key.spans[i].$2) {
          return (key, key.parentCount + i);
        }
      }
    }
    return null;
  }

  /// The key whose value is at ([line], [column]).
  ConfigKey? valueAt(int line, int column) {
    for (final key in keys) {
      if (key.line == line &&
          key.value != null &&
          column >= key.valueStart &&
          column <= key.valueEnd) {
        return key;
      }
    }
    return null;
  }

  /// The placeholder or expression of [key]'s value at [column], with the
  /// value it is in; `null` when there is none.
  static (TemplatePart, String)? templateAt(ConfigKey key, int column) {
    final value = key.value!;
    if (!value.contains(r'${') && !value.contains('#{')) {
      return null;
    }
    final relative = column - key.valueStart;
    for (final part in scanTemplate(value).reversed) {
      if (relative >= part.start && relative <= part.end) {
        return (part, value);
      }
    }
    return null;
  }
}
