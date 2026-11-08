import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';

/// The `morph` change of a run of [count] characters at [progress] (0 to
/// 1): each character starts [stagger] (a share of the whole change) after
/// the one before it, runs through [glyphs] and settles on the new text.
/// `ThemeText` morphs one line with it; `MarkdownView` a whole page, line
/// after line (`motion.content-change: morph`), the pieces of a line (a
/// link, a word in bold) each at their [of] offset in the run.
///
/// [seed] picks the glyphs (the animation's frame), so they flicker as it
/// runs; [keepUnchanged] leaves the characters that are the same in the
/// old and the new text alone.
final class TextMorph {
  /// The change of [count] characters at [progress].
  const TextMorph({
    required this.count,
    required this.progress,
    this.stagger = 0.02,
    this.seed = 0,
    this.keepUnchanged = false,
    this.glyphs = TextChangeSpec.defaultGlyphs,
  });

  /// How many characters the whole run has.
  final int count;

  /// How far the change is, 0 to 1.
  final double progress;

  /// The share of the change one character starts later than the one
  /// before it.
  final double stagger;

  /// Picks the glyphs shown.
  final int seed;

  /// Whether a character that does not change stays as it is.
  final bool keepUnchanged;

  /// The glyphs a changing character runs through.
  final String glyphs;

  /// How much of the change the starts of the characters take: the rest is
  /// the window each character changes in, never less than 15 percent.
  double get spread => (stagger * (count - 1)).clamp(0.0, 0.85);

  /// Whether every character has settled.
  bool get settled => progress >= 1;

  /// Whether no character has started.
  bool get waiting => progress <= 0;

  /// The characters [offset] into the run, changing from [from] to [to]
  /// (the longer of the two gives their number), as they show at
  /// [progress]; the trailing spaces of a whole line trimmed ([trim]),
  /// those of a piece of one kept.
  String of(String from, String to, {int offset = 0, bool trim = true}) {
    final pool = glyphs.characters.toList();
    final a = from.characters.toList();
    final b = to.characters.toList();
    final length = a.length > b.length ? a.length : b.length;
    if (length == 0) {
      return '';
    }
    final window = 1 - spread;
    final out = StringBuffer();
    for (var i = 0; i < length; i++) {
      final index = offset + i;
      final start = count <= 1 ? 0.0 : spread * index / (count - 1);
      final local = (progress - start) / window;
      final old = i < a.length ? a[i] : '';
      final next = i < b.length ? b[i] : '';
      if (keepUnchanged && old == next) {
        out.write(old);
      } else if (local <= 0) {
        out.write(old);
      } else if (local >= 1) {
        out.write(next);
      } else if (next.trim().isEmpty && old.trim().isEmpty) {
        out.write(next.isEmpty ? old : next);
      } else {
        out.write(pool[(seed * 7 + index * 13) % pool.length]);
      }
    }
    final shown = out.toString();
    return trim ? shown.trimRight() : shown;
  }

  /// [span] with every text in it morphed from nothing, the pieces one
  /// after the other in the run from [offset]; the styles, recognizers and
  /// widgets kept. Returns the span and the offset after it.
  (InlineSpan, int) spanOf(InlineSpan span, {int offset = 0}) {
    if (span is! TextSpan) {
      return (span, offset);
    }
    var next = offset;
    final text = span.text;
    String? shown;
    if (text != null) {
      shown = of('', text, offset: next, trim: false);
      next += text.characters.length;
    }
    List<InlineSpan>? children;
    if (span.children case final list?) {
      children = [];
      for (final child in list) {
        final (morphed, after) = spanOf(child, offset: next);
        children.add(morphed);
        next = after;
      }
    }
    return (
      TextSpan(
        text: shown,
        style: span.style,
        recognizer: span.recognizer,
        mouseCursor: span.mouseCursor,
        semanticsLabel: span.semanticsLabel,
        locale: span.locale,
        spellOut: span.spellOut,
        children: children,
      ),
      next,
    );
  }

  /// How many characters [span] has, its children included.
  static int lengthOf(InlineSpan span) {
    if (span is! TextSpan) {
      return 0;
    }
    var length = span.text?.characters.length ?? 0;
    for (final child in span.children ?? const <InlineSpan>[]) {
      length += lengthOf(child);
    }
    return length;
  }
}
