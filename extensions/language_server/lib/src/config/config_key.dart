/// A key of a config file as the editor reads it, with the place of its
/// parts on its line: what completion, hovers, definitions and checks of
/// config files work on.
final class ConfigKey {
  /// The key at [line] whose whole path is [segments].
  ConfigKey({
    required this.line,
    required this.segments,
    required this.parentCount,
    required this.spans,
    this.value,
    this.valueStart = 0,
    this.quoted = false,
    this.complex = false,
    this.indent = 0,
  });

  /// The zero-based line of the key.
  final int line;

  /// The whole path of the key.
  final List<String> segments;

  /// How many of [segments] come from lines above.
  final int parentCount;

  /// Start and end column of each segment this line adds.
  final List<(int, int)> spans;

  /// The scalar value as text, without quotes; `null` for a group.
  final String? value;

  /// The column where [value] starts.
  final int valueStart;

  /// Whether [value] was quoted.
  final bool quoted;

  /// A flow list, an anchor, a tag or a block scalar: the value is not
  /// checked.
  final bool complex;

  /// The column of the key.
  final int indent;

  /// The column just after [value].
  int get valueEnd => valueStart + (value?.length ?? 0);
}

/// The dot-separated parts of [key], each with its start and end column
/// on the line, where [key] starts at [column].
List<(String, int, int)> dottedParts(String key, int column) {
  final result = <(String, int, int)>[];
  var start = 0;
  for (var i = 0; i <= key.length; i++) {
    if (i == key.length || key[i] == '.') {
      if (i > start) {
        result.add((key.substring(start, i), column + start, column + i));
      }
      start = i + 1;
    }
  }
  return result;
}

/// The column of the key of [line], after any list dashes.
int keyIndentOf(String line) {
  var content = line.replaceAll('\r', '');
  var indent = content.length - content.trimLeft().length;
  content = content.trimLeft();
  while (content == '-' || content.startsWith('- ')) {
    final rest = content.length == 1 ? '' : content.substring(2);
    indent += 2 + (rest.length - rest.trimLeft().length);
    content = rest.trimLeft();
  }
  return indent;
}
