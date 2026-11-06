// ThemeText: a text that changes the theme's way (motion.text-change):
// at once by default, a cross-fade, or a morph character after character
// from the start of the line; at once with "reduce motion".
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

Widget _app(Map<String, String> theme, String text, {bool reduce = false}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: reduce),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SpringTheme(
          data: SpringThemes(theme).data('light'),
          child: ThemeText(text),
        ),
      ),
    );

String _shown(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text))) text.data!,
].join('|');

void main() {
  const morph = {
    'motion.text-change.type': 'morph',
    'motion.text-change.duration': '400ms',
    'motion.text-change.curve': 'linear',
    'motion.text-change.stagger': '20ms',
  };

  test('motion.text-change: a kind, or a map; none by default', () {
    expect(
      SpringThemes(const {}).data('light').textChange.type,
      TextChangeType.none,
    );
    expect(
      SpringThemes(const {'motion.text-change': 'fade'})
          .data('light')
          .textChange
          .type,
      TextChangeType.fade,
    );
    final spec = SpringThemes(morph).data('light').textChange;
    expect(spec.type, TextChangeType.morph);
    expect(spec.duration, const Duration(milliseconds: 400));
    expect(spec.stagger, const Duration(milliseconds: 20));
    expect(
      () => SpringThemes(const {'motion.text-change.speed': '1'}).data('light'),
      throwsA(isA<ThemePropertyException>()),
    );
  });

  test('morph: the old text before, the new after, the start first', () {
    expect(ThemeText.morph('Docs', 'ドキュメント', 0), 'Docs');
    expect(ThemeText.morph('Docs', 'ドキュメント', 1), 'ドキュメント');
    final middle = ThemeText.morph('aaaaaaaa', 'bbbbbbbb', 0.5, stagger: 0.1);
    expect(middle, startsWith('b'));
    expect(middle, endsWith('a'));
    expect(
      ThemeText.morph('a b', 'c d', 0.5, stagger: 0).characters.elementAt(1),
      ' ',
    );
  });

  test('morph keep-unchanged: the characters that stay do not flicker', () {
    for (final progress in [0.1, 0.3, 0.5, 0.7, 0.9]) {
      final shown = ThemeText.morph(
        'DOCS / CORE / @COMPONENT',
        'DOCS / CORE / @SCOPE',
        progress,
        stagger: 0.02,
        keepUnchanged: true,
      );
      expect(shown, startsWith('DOCS / CORE / @'), reason: '$progress');
      // By default the wave runs over the whole line.
      expect(
        ThemeText.morph(
          'DOCS / CORE / @COMPONENT',
          'DOCS / CORE / @SCOPE',
          0.3,
          stagger: 0.02,
        ),
        isNot(startsWith('DOCS')),
      );
    }
  });

  test('morph glyphs and how long each shows come from the theme', () {
    final spec = SpringThemes(const {
      'motion.text-change.type': 'morph',
      'motion.text-change.glyphs': r'01$ab',
      'motion.text-change.glyph-duration': '80ms',
    }).data('light').textChange;
    // Taken as written: `$ab` is no reference.
    expect(spec.glyphs, r'01$ab');
    expect(spec.glyphDuration, const Duration(milliseconds: 80));
    final shown = ThemeText.morph(
      'aaaaaaaa',
      'zzzzzzzz',
      0.5,
      stagger: 0,
      glyphs: '#',
    );
    expect(shown, '########');
    for (final (key, value) in [
      ('motion.text-change.glyph-duration', '0ms'),
      ('motion.text-change.glyph-duration', 'soon'),
    ]) {
      expect(
        () => SpringThemes({
          'motion.text-change.type': 'morph',
          key: value,
        }).data('light'),
        throwsA(isA<ThemePropertyException>()),
        reason: key,
      );
    }
  });

  testWidgets('none: the new text at once', (tester) async {
    await tester.pumpWidget(_app(const {}, 'Docs'));
    await tester.pumpWidget(_app(const {}, 'ドキュメント'));
    expect(_shown(tester), 'ドキュメント');
  });

  testWidgets('morph: glyphs while it runs, the new text at the end', (
    tester,
  ) async {
    await tester.pumpWidget(_app(morph, 'Packages'));
    await tester.pumpWidget(_app(morph, 'パッケージ'));
    await tester.pump(const Duration(milliseconds: 150));
    final middle = _shown(tester);
    expect(middle, isNot('Packages'));
    expect(middle, isNot('パッケージ'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_shown(tester), 'パッケージ');
  });

  testWidgets('fade: both texts while it runs', (tester) async {
    const fade = {'motion.text-change': 'fade'};
    await tester.pumpWidget(_app(fade, 'Docs'));
    await tester.pumpWidget(_app(fade, 'ドキュメント'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_shown(tester), 'Docs|ドキュメント');
    await tester.pumpAndSettle();
    expect(_shown(tester), 'ドキュメント');
  });

  testWidgets('reduce motion: at once', (tester) async {
    await tester.pumpWidget(_app(morph, 'Docs', reduce: true));
    await tester.pumpWidget(_app(morph, 'ドキュメント', reduce: true));
    expect(_shown(tester), 'ドキュメント');
  });
}
