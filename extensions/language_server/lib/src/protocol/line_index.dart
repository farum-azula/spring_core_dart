/// Where the lines of a text start, to turn the protocol's positions (a
/// zero-based line and a column in UTF-16 units) into offsets of the text
/// and back. Dart strings count UTF-16 units too, so a column is an offset
/// within its line.
final class LineIndex {
  /// The index of [text].
  LineIndex(this.text) : _starts = _lineStarts(text);

  /// The text indexed.
  final String text;

  final List<int> _starts;

  /// The number of lines (a text ending with a line break has an empty last
  /// line).
  int get lineCount => _starts.length;

  /// The offset of [line], [column], clamped to the text: a column past the
  /// end of its line is the line's end, a line past the last is the text's
  /// end.
  int offsetOf(int line, int column) {
    if (line < 0) {
      return 0;
    }
    if (line >= _starts.length) {
      return text.length;
    }
    final lineEnd = line + 1 < _starts.length
        ? _starts[line + 1] - 1
        : text.length;
    return (_starts[line] + column).clamp(_starts[line], lineEnd);
  }

  /// The line and column of [offset] (clamped to the text).
  ({int line, int column}) positionOf(int offset) {
    final clamped = offset.clamp(0, text.length);
    var low = 0;
    var high = _starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (_starts[middle] <= clamped) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return (line: low, column: clamped - _starts[low]);
  }

  static List<int> _lineStarts(String text) => [
    0,
    for (var i = 0; i < text.length; i++)
      if (text.codeUnitAt(i) == 0x0A) i + 1,
  ];
}
