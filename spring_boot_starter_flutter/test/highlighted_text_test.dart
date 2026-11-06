// HighlightedText: the stretches given, in order, merged when they
// overlap, cut to the text.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

void main() {
  const bold = TextStyle(fontWeight: FontWeight.w700);

  List<(String, bool)> parts(String text, List<TextRange> ranges) => [
    for (final span in HighlightedText.spans(text, ranges, bold))
      (span.text!, span.style == bold),
  ];

  test('plain and highlighted stretches, in order', () {
    expect(
      parts('a bean factory', const [
        TextRange(start: 7, end: 14),
        TextRange(start: 2, end: 6),
      ]),
      [('a ', false), ('bean', true), (' ', false), ('factory', true)],
    );
  });

  test('overlaps merge; ranges past the end are cut; none: one span', () {
    expect(
      parts('context', const [
        TextRange(start: 0, end: 4),
        TextRange(start: 2, end: 99),
      ]),
      [('cont', true), ('ext', true)],
    );
    expect(parts('plain', const []), [('plain', false)]);
  });

  testWidgets('shows the text', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: HighlightedText(
          'find me',
          highlights: [TextRange(start: 5, end: 7)],
        ),
      ),
    );
    expect(find.text('find me', findRichText: true), findsOneWidget);
  });
}
