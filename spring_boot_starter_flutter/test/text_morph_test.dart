// TextMorph: the glyph-by-glyph change over a run of characters, shared by
// ThemeText (a line) and MarkdownView (a page, line after line): the
// pieces of a span morph as one run, their styles and recognizers kept.
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

void main() {
  test('of: the old before, the new after; the run spreads by offset', () {
    const morph = TextMorph(count: 20, progress: 0.5, stagger: 0.05);
    // The first characters of the run have settled, the last have not.
    expect(morph.of('', 'abcde'), startsWith('a'));
    expect(morph.of('', 'vwxyz', offset: 15), '');
    expect(morph.spread, 0.85);
    expect(const TextMorph(count: 3, progress: 0).waiting, isTrue);
    expect(const TextMorph(count: 3, progress: 1).settled, isTrue);
    expect(ThemeText.morph('Docs', 'ドキュメント', 1), 'ドキュメント');
  });

  test('spanOf: every piece typed in turn, styles and recognizers kept', () {
    final tap = TapGestureRecognizer();
    addTearDown(tap.dispose);
    final span = TextSpan(
      children: [
        const TextSpan(text: 'See ', style: TextStyle(fontSize: 10)),
        TextSpan(
          text: 'docs',
          recognizer: tap,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const TextSpan(text: ' now'),
      ],
    );
    expect(TextMorph.lengthOf(span), 12);
    final done = TextMorph(count: 12, progress: 1).spanOf(span);
    expect(done.$2, 12);
    expect(done.$1.toPlainText(), 'See docs now');
    final link = (done.$1 as TextSpan).children![1] as TextSpan;
    expect(link.recognizer, same(tap));
    expect(link.style?.fontWeight, FontWeight.bold);

    // Half way with a strong stagger: the first piece is in, the last not.
    final half =
        TextMorph(count: 12, progress: 0.5, stagger: 0.2).spanOf(span).$1
            as TextSpan;
    expect((half.children![0] as TextSpan).text, 'See ');
    expect((half.children![2] as TextSpan).text, '');
    expect(TextMorph(count: 12, progress: 0).spanOf(span).$1.toPlainText(), '');
  });
}
