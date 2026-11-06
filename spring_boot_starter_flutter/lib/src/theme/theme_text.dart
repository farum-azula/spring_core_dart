import 'package:flutter/widgets.dart';
import 'package:spring_boot_starter_flutter/src/theme/spring_themes.dart';
import 'package:spring_boot_starter_flutter/src/text/highlighted_text.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_animation.dart';

/// A [Text] that changes its text the theme's way (`motion.text-change`):
/// at once, with a cross-fade, or character after character from the
/// start of the line (`morph`), each running through a few glyphs before
/// it settles. The change is when the same widget gets another text: the
/// app's language switched, a value updated.
///
/// ```dart
/// ThemeText(context.messages.home.title, style: theme.typography.displaySmall);
/// ```
///
/// [highlights] mark stretches of the text in [highlightStyle] (the words
/// a search found), once the change has settled.
///
/// With "reduce motion" (`MediaQuery.disableAnimations`) the text changes
/// at once.
class ThemeText extends StatefulWidget {
  /// Shows [data] like [Text], with [style], [textAlign], [maxLines],
  /// [overflow] and [softWrap].
  const ThemeText(
    this.data, {
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.highlights = const [],
    this.highlightStyle = const TextStyle(fontWeight: FontWeight.w700),
    super.key,
  });

  /// Stretches of [data] shown in [highlightStyle].
  final List<TextRange> highlights;

  /// What a highlight adds to [style].
  final TextStyle highlightStyle;

  /// The text.
  final String data;

  /// As [Text.style].
  final TextStyle? style;

  /// As [Text.textAlign].
  final TextAlign? textAlign;

  /// As [Text.maxLines].
  final int? maxLines;

  /// As [Text.overflow].
  final TextOverflow? overflow;

  /// As [Text.softWrap].
  final bool? softWrap;

  /// The text `morph` shows at [progress] (0 to 1) of the change from
  /// [from] to [to], with [stagger] the share of the change one character
  /// starts later than the one before it. [seed] picks the glyphs (the
  /// animation's frame), so they flicker as it runs.
  static String morph(
    String from,
    String to,
    double progress, {
    double stagger = 0.02,
    int seed = 0,
    bool keepUnchanged = false,
    String glyphs = TextChangeSpec.defaultGlyphs,
  }) {
    final pool = glyphs.characters.toList();
    final a = from.characters.toList();
    final b = to.characters.toList();
    final count = a.length > b.length ? a.length : b.length;
    if (count == 0) {
      return '';
    }
    final spread = (stagger * (count - 1)).clamp(0.0, 0.85);
    final window = 1 - spread;
    final out = StringBuffer();
    for (var i = 0; i < count; i++) {
      final start = count == 1 ? 0.0 : spread * i / (count - 1);
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
        out.write(pool[(seed * 7 + i * 13) % pool.length]);
      }
    }
    return out.toString().trimRight();
  }

  @override
  State<ThemeText> createState() => _ThemeTextState();
}

class _ThemeTextState extends State<ThemeText>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, value: 1);
  String _from = '';
  TextChangeSpec _spec = const TextChangeSpec();

  @override
  void didUpdateWidget(ThemeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data == widget.data) {
      return;
    }
    final spec =
        SpringTheme.maybeOf(context)?.textChange ?? const TextChangeSpec();
    if (spec.type == TextChangeType.none ||
        spec.duration == Duration.zero ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _controller.value = 1;
      return;
    }
    _from = _controller.isAnimating ? _shown(oldWidget.data) : oldWidget.data;
    _spec = spec;
    _controller
      ..duration = spec.duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _progress => _spec.curve.transform(_controller.value);

  String _shown(String to) => ThemeText.morph(
    _from,
    to,
    _progress,
    stagger: _spec.duration == Duration.zero
        ? 0
        : _spec.stagger.inMicroseconds / _spec.duration.inMicroseconds,
    seed:
        (_controller.value *
                _spec.duration.inMicroseconds /
                _spec.glyphDuration.inMicroseconds)
            .floor(),
    keepUnchanged: _spec.keepUnchanged,
    glyphs: _spec.glyphs,
  );

  Text _text(String data) => Text(
    data,
    style: widget.style,
    textAlign: widget.textAlign,
    maxLines: widget.maxLines,
    overflow: widget.overflow,
    softWrap: widget.softWrap,
  );

  Widget _settled() => widget.highlights.isEmpty
      ? _text(widget.data)
      : Text.rich(
          TextSpan(
            children: HighlightedText.spans(
              widget.data,
              widget.highlights,
              widget.highlightStyle,
            ),
          ),
          style: widget.style,
          textAlign: widget.textAlign,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          softWrap: widget.softWrap,
        );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      if (_controller.value >= 1) {
        return _settled();
      }
      return switch (_spec.type) {
        TextChangeType.morph => _text(_shown(widget.data)),
        TextChangeType.fade => Stack(
          children: [
            Opacity(opacity: 1 - _progress, child: _text(_from)),
            Opacity(opacity: _progress, child: _text(widget.data)),
          ],
        ),
        TextChangeType.none => _text(widget.data),
      };
    },
  );
}
