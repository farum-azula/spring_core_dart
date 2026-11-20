import 'package:dart_spring_language_server/src/symbols/source_range.dart';

/// Text to put in place of [range] of its file; an insertion when the
/// range is empty.
final class TextEdit {
  /// [range] replaced by [newText].
  const TextEdit(this.range, this.newText);

  /// What is replaced.
  final SourceRange range;

  /// What replaces it.
  final String newText;
}

/// A change that fixes a problem, which the editor offers as a quick fix:
/// [title] in its menu, [edits] applied when chosen (in one file or
/// several).
final class Fix {
  /// A fix named [title] that makes [edits].
  const Fix(this.title, this.edits);

  /// The fix of a misspelt name: [range] replaced by [text], the name it
  /// was probably meant to be.
  Fix.replace(SourceRange range, String text)
    : this("Change to '$text'", [TextEdit(range, text)]);

  /// What the editor shows.
  final String title;

  /// What it changes.
  final List<TextEdit> edits;

  /// The fixes of a did-you-mean: one replacing [range] with [guess], none
  /// without a guess.
  static List<Fix> suggesting(SourceRange range, String? guess) => [
    if (guess != null) Fix.replace(range, guess),
  ];
}
