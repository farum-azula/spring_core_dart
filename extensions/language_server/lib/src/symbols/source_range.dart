/// A span of text in a file, in LSP terms: zero-based lines, and columns
/// counted in UTF-16 code units.
///
/// Definitions and diagnostics are reported as ranges; the server turns
/// them into LSP locations.
final class SourceRange {
  /// The span of [path] from [startLine], [startColumn] to [endLine],
  /// [endColumn].
  const SourceRange(
    this.path,
    this.startLine,
    this.startColumn,
    this.endLine,
    this.endColumn,
  );

  /// The absolute path of the file.
  final String path;

  /// The zero-based line where the span starts.
  final int startLine;

  /// The zero-based column where the span starts.
  final int startColumn;

  /// The zero-based line where the span ends.
  final int endLine;

  /// The zero-based column just after the span's last character.
  final int endColumn;

  @override
  String toString() => '$path:$startLine:$startColumn';
}
