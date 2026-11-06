import 'package:flutter/widgets.dart';

/// A text with stretches of it highlighted: the words a search found, the
/// part of a name that was typed. [highlights] are ranges of [text]
/// (overlapping or out of order is fine); they take [highlightStyle] over
/// [style], bold by default.
///
/// ```dart
/// final snippet = hit.snippet('body');
/// HighlightedText(
///   snippet.text,
///   highlights: [for (final r in snippet.ranges) TextRange(start: r.start, end: r.end)],
///   highlightStyle: TextStyle(color: theme.colors.primary),
/// )
/// ```
class HighlightedText extends StatelessWidget {
  /// [text] with [highlights].
  const HighlightedText(
    this.text, {
    this.highlights = const [],
    this.style,
    this.highlightStyle = const TextStyle(fontWeight: FontWeight.w700),
    this.maxLines,
    this.overflow,
    this.textAlign,
    super.key,
  });

  /// The text.
  final String text;

  /// The stretches highlighted.
  final List<TextRange> highlights;

  /// The text's style.
  final TextStyle? style;

  /// What a highlight adds to [style].
  final TextStyle highlightStyle;

  /// At most this many lines.
  final int? maxLines;

  /// How a text that does not fit ends.
  final TextOverflow? overflow;

  /// The alignment.
  final TextAlign? textAlign;

  /// [text] cut into spans: plain, then highlighted, and so on.
  static List<TextSpan> spans(
    String text,
    List<TextRange> highlights,
    TextStyle highlightStyle,
  ) {
    final ranges = [
      for (final range in highlights)
        if (range.isValid && range.start < text.length)
          TextRange(start: range.start, end: range.end.clamp(0, text.length)),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final spans = <TextSpan>[];
    var position = 0;
    for (final range in ranges) {
      if (range.end <= position) {
        continue;
      }
      final start = range.start < position ? position : range.start;
      if (start > position) {
        spans.add(TextSpan(text: text.substring(position, start)));
      }
      spans.add(
        TextSpan(text: text.substring(start, range.end), style: highlightStyle),
      );
      position = range.end;
    }
    if (position < text.length) {
      spans.add(TextSpan(text: text.substring(position)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(style: style, children: spans(text, highlights, highlightStyle)),
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
  );
}
