// motion.content-change: the kinds by name (an app's own registered), the
// map form, a wrong kind or key named; MarkdownView.resource keeps the
// page shown until the next is read, then changes the theme's way.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

ContentChangeSpec _spec(Map<String, String> values) =>
    SpringThemes(values).data('light').contentChange;

void main() {
  tearDown(ContentTransitions.reset);

  test('a kind alone, the map form, nothing written', () {
    expect(_spec({'motion.content-change': 'fade'}).type, 'fade');
    final spec = _spec({
      'motion.content-change.type': 'fade-up',
      'motion.content-change.duration': '120ms',
      'motion.content-change.curve': 'linear',
    });
    expect(
      spec,
      const ContentChangeSpec(
        type: 'fadeup',
        duration: Duration(milliseconds: 120),
        curve: Curves.linear,
      ),
    );
    expect(_spec(const {}).type, 'none');
  });

  test('motion.scroll-to-top: an animation, none, or the default', () {
    AnimationSpec? scroll(Map<String, String> values) =>
        SpringThemes(values).data('light').scrollToTop;
    expect(scroll(const {}), SpringThemeData.defaultScrollToTop);
    expect(scroll(const {'motion.scroll-to-top': 'none'}), isNull);
    expect(
      scroll(const {
        'motion.scroll-to-top.duration': '250ms',
        'motion.scroll-to-top.curve': 'linear',
      }),
      const AnimationSpec(duration: Duration(milliseconds: 250)),
    );
    expect(
      () => scroll(const {'motion.scroll-to-top': 'fast'}),
      throwsA(isA<ThemePropertyException>()),
    );
  });

  test("an app's own kind; a wrong kind or key is named", () {
    ContentTransitions.register(
      'Scale',
      (child, animation) => ScaleTransition(scale: animation, child: child),
    );
    expect(_spec({'motion.content-change': 'scale'}).type, 'scale');
    for (final (values, problem) in [
      ({'motion.content-change': 'spin'}, 'a kind: none, fade, fade-up'),
      ({'motion.content-change.speed': '2'}, 'type, duration or curve'),
    ]) {
      expect(
        () => _spec(values),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => '$e',
            'message',
            allOf(
              contains('spring.flutter.theme.motion.content'),
              contains(problem),
            ),
          ),
        ),
      );
    }
  });

  testWidgets('the page stays until the next is read, then fades', (
    tester,
  ) async {
    final context = await SpringApplication([
      BeanModule(
        'test',
        const [],
        resources: {
          'content/a.md': EmbeddedResource.text(
            '# Alpha\n\n## Why\n\n${'Text.\n\n' * 20}',
          ),
          'content/b.md': const EmbeddedResource.text('# Beta\n\n## Why\n'),
        },
      ),
    ], bannerMode: BannerMode.off).runAsync(const []);
    addTearDown(context.close);
    final outline = MarkdownOutline();
    addTearDown(outline.dispose);
    final theme = SpringThemes({
      'motion.content-change': 'fade',
    }).data('light');
    Widget at(String file) => SpringScope(
      applicationContext: context,
      child: SpringTheme(
        data: theme,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            // An outline: both pages have a heading `Why`, each with its
            // own key while both are on screen.
            child: MarkdownView.resource(
              file,
              selectable: false,
              outline: outline,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(at('resources:content/a.md'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final tall = tester.getSize(find.byType(MarkdownView)).height;

    await tester.pumpWidget(at('resources:content/b.md'));
    // Not read yet: Alpha stays, the view keeps its height.
    expect(find.text('Alpha'), findsOneWidget);
    expect(tester.getSize(find.byType(MarkdownView)).height, tall);

    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Both while one goes and the other comes.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
    expect(outline.show('why'), isTrue);
  });
}
