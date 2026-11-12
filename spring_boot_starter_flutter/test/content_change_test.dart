// motion.content-change: the kinds by name (an app's own registered), the
// map form, a wrong kind or key named; MarkdownView.resource keeps the
// page shown until the next is read, then changes the theme's way.
import 'package:flutter/widgets.dart';
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

  test(
    'morph: stagger and delay in the map form; the widget shows at once',
    () {
      final spec = _spec({
        'motion.content-change.type': 'morph',
        'motion.content-change.duration': '1.2s',
        'motion.content-change.stagger': '40ms',
        'motion.content-change.delay': '650ms',
      });
      expect(spec.morphs, isTrue);
      expect(spec.stagger, const Duration(milliseconds: 40));
      expect(spec.delay, const Duration(milliseconds: 650));
      expect(
        _spec({'motion.content-change': 'morph'}).stagger,
        const Duration(milliseconds: 30),
      );
      expect(ContentTransitions.lookup('morph'), isNotNull);
    },
  );

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
      ({'motion.content-change': 'spin'}, 'a kind: none, fade, fade-up, morph'),
      (
        {'motion.content-change.speed': '2'},
        'type, duration, curve, stagger or delay',
      ),
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

  testWidgets('morph: the page has its height from the first frame, its '
      'lines type in one after the other after the delay', (tester) async {
    final context = await SpringApplication([
      BeanModule(
        'test',
        const [],
        resources: {
          'content/a.md': const EmbeddedResource.text(
            '# Alpha\n\nText one.\n\n- item\n',
          ),
        },
      ),
    ], bannerMode: BannerMode.off).runAsync(const []);
    addTearDown(context.close);
    final theme = SpringThemes({
      'motion.content-change.type': 'morph',
      'motion.content-change.duration': '400ms',
      'motion.content-change.curve': 'linear',
      'motion.content-change.stagger': '100ms',
      'motion.content-change.delay': '200ms',
    }).data('light');
    final glyphs = RegExp('[${RegExp.escape(TextChangeSpec.defaultGlyphs)}]');
    final typing = find.byWidgetPredicate(
      (w) => w is RichText && glyphs.hasMatch(w.text.toPlainText()),
    );
    await tester.pumpWidget(
      SpringScope(
        applicationContext: context,
        child: SpringTheme(
          data: theme,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: SingleChildScrollView(
              child: MarkdownView.resource(
                'resources:content/a.md',
                selectable: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    // The first frame: every line in place, none shown yet.
    final height = tester.getSize(find.byType(MarkdownView)).height;
    expect(height, greaterThan(0));
    expect(find.text('Alpha'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Visibility && !w.visible),
      findsNWidgets(4),
    ); // the heading, the text, the marker and the item
    // The change starts counting at the frame after the page's first.
    await tester.pump(const Duration(milliseconds: 150));
    // In the delay: still nothing shown.
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      find.byWidgetPredicate((w) => w is Visibility && !w.visible),
      findsNWidgets(4),
    );
    expect(typing, findsNothing);
    // 4 lines 100ms apart over 400ms: the starts take 75 percent, each
    // line types over 100ms. At 250ms in, the heading types, the item
    // waits.
    await tester.pump(const Duration(milliseconds: 100));
    expect(typing, findsOneWidget);
    expect(tester.getSize(find.byType(MarkdownView)).height, height);
    expect(find.text('item'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(typing, findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Text one.'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is Visibility && !w.visible),
      findsNothing,
    );
    expect(tester.getSize(find.byType(MarkdownView)).height, height);
  });

  testWidgets('morph with reduced motion: the page at once', (tester) async {
    final context = await SpringApplication([
      BeanModule(
        'test',
        const [],
        resources: {
          'content/a.md': const EmbeddedResource.text('# Alpha\n'),
        },
      ),
    ], bannerMode: BannerMode.off).runAsync(const []);
    addTearDown(context.close);
    final theme = SpringThemes({
      'motion.content-change': 'morph',
    }).data('light');
    await tester.pumpWidget(
      SpringScope(
        applicationContext: context,
        child: SpringTheme(
          data: theme,
          child: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MarkdownView.resource(
                'resources:content/a.md',
                selectable: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.byType(Visibility), findsNothing);
  });

  testWidgets('page-transition content: the screen comes in as the content '
      'change does; none or morph at once', (tester) async {
    Widget built(String change) {
      final theme = SpringThemes({'motion.content-change': change})
          .data('light');
      return SpringTheme(
        data: theme,
        child: Builder(
          builder: (context) =>
              const ContentPageTransitionsBuilder().buildTransitions<void>(
                PageRouteBuilder<void>(
                  pageBuilder: (_, _, _) => const Text('x'),
                ),
                context,
                const AlwaysStoppedAnimation(0.5),
                const AlwaysStoppedAnimation(0),
                const Text('x', textDirection: TextDirection.ltr),
              ),
        ),
      );
    }

    await tester.pumpWidget(built('fade-up'));
    expect(find.byType(FadeTransition), findsOneWidget);
    expect(find.byType(SlideTransition), findsOneWidget);
    await tester.pumpWidget(built('morph'));
    expect(find.byType(FadeTransition), findsNothing);
    await tester.pumpWidget(built('none'));
    expect(find.byType(FadeTransition), findsNothing);
  });
}
