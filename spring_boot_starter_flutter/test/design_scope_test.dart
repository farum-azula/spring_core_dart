// DesignScope: what the design library of the app gives the starter's own
// widgets. MarkdownView without one, as in an app of type widgets, takes
// its text styles from the SpringTheme and is selectable with the
// starter's own handles; with one it takes the design's.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

const _markdown = '''
# One

## Two

### Three

#### Four

##### Five

###### Six

body
''';

/// An app without a design library showing [child] in theme [data], as a
/// page of its navigator.
Widget _app(
  SpringThemeData data,
  Widget child, {
  Locale locale = const Locale('en'),
}) => WidgetsApp(
  color: const Color(0xFF000000),
  locale: locale,
  supportedLocales: const [Locale('en'), Locale('ja'), Locale('ar')],
  builder: (context, page) => SpringTheme(data: data, child: page!),
  pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
    settings: settings,
    pageBuilder: (context, _, _) => builder(context),
  ),
  home: SingleChildScrollView(child: child),
);

TextStyle _styleOf(WidgetTester tester, String text) => tester
    .widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == text,
      ),
    )
    .text
    .style!;

// The app widget of a design of the test, as Material's localizations
// mark a MaterialApp: controls of that design find it above them.
final class _App extends InheritedWidget {
  const _App(this.design, {required super.child});

  final String design;

  static bool isAbove(BuildContext context, String design) =>
      context.getInheritedWidgetOfExactType<_App>()?.design == design;

  @override
  bool updateShouldNotify(_App oldWidget) => design != oldWidget.design;
}

final class _Controls implements DesignControls {
  _Controls([this.design]);

  /// The design whose [_App] these controls find above them; `null` for
  /// controls that find none.
  final String? design;

  @override
  bool isAppAbove(BuildContext context) =>
      design != null && _App.isAbove(context, design!);

  @override
  Widget textField(BuildContext context, DesignTextField field) =>
      Text(field.label);

  @override
  Widget filledButton(BuildContext context, DesignButton button) =>
      Text(button.label);

  @override
  Color errorColor(BuildContext context) => const Color(0xFFFF0000);

  @override
  Widget surface(BuildContext context, Widget child) => child;
}

void main() {
  group('MarkdownView without a scope', () {
    testWidgets('the styles of the theme, with the sizes of the type scale', (
      tester,
    ) async {
      final data = SpringThemes(const {
        'typography.font-family': 'Inter',
        'themes.night.brightness': 'dark',
      }).data('night');
      await tester.pumpWidget(
        _app(data, const MarkdownView(_markdown, selectable: false)),
      );
      expect(find.byType(DesignScope), findsNothing);
      // The headings: headline large to small, then title large to small.
      for (final (text, style) in [
        ('One', 'headlineLarge'),
        ('Two', 'headlineMedium'),
        ('Three', 'headlineSmall'),
        ('Four', 'titleLarge'),
        ('Five', 'titleMedium'),
        ('Six', 'titleSmall'),
        ('body', 'bodyLarge'),
      ]) {
        final shown = _styleOf(tester, text);
        final expected = data.localizedTextStyle(
          style,
          TextScript.englishLike,
        );
        expect(shown.fontSize, expected.fontSize, reason: text);
        expect(shown.fontWeight, expected.fontWeight, reason: text);
        expect(shown.height, expected.height, reason: text);
        expect(shown.letterSpacing, expected.letterSpacing, reason: text);
        expect(shown.fontFamily, 'Inter', reason: text);
        expect(shown.color, const Color(0xFFE6E0E9), reason: text);
        expect(shown.textBaseline, TextBaseline.alphabetic, reason: text);
      }
      expect(
        [
          for (final text in ['One', 'Two', 'Three', 'Four', 'Five', 'Six'])
            _styleOf(tester, text).fontSize,
        ],
        [32, 28, 24, 22, 16, 14],
      );
      expect(_styleOf(tester, 'body').fontSize, 16);
    });

    testWidgets('the sizes of the locale\'s script', (tester) async {
      final data = SpringThemes(const {}).data('light');
      for (final (locale, baseline) in [
        (const Locale('ja'), TextBaseline.ideographic),
        (const Locale('ar'), TextBaseline.alphabetic),
        (const Locale('en'), TextBaseline.alphabetic),
      ]) {
        await tester.pumpWidget(
          _app(
            data,
            const MarkdownView('# One\n\nbody', selectable: false),
            locale: locale,
          ),
        );
        await tester.pump();
        expect(
          Localizations.localeOf(tester.element(find.byType(MarkdownView))),
          locale,
        );
        expect(
          _styleOf(tester, 'body').textBaseline,
          baseline,
          reason: '$locale',
        );
        expect(
          _styleOf(tester, 'One').textBaseline,
          baseline,
          reason: '$locale',
        );
      }
    });

    testWidgets('what typography.* sets is kept over the scale', (
      tester,
    ) async {
      final data = SpringThemes(const {
        'typography.body-large.size': '19',
        'typography.headline-large.weight': 'bold',
      }).data('light');
      await tester.pumpWidget(
        _app(data, const MarkdownView('# One\n\nbody', selectable: false)),
      );
      expect(_styleOf(tester, 'body').fontSize, 19);
      expect(_styleOf(tester, 'body').height, 1.5);
      expect(_styleOf(tester, 'One').fontSize, 32);
      expect(_styleOf(tester, 'One').fontWeight, FontWeight.w700);
    });

    testWidgets('selectable with the starter\'s own handles', (tester) async {
      final data = SpringThemes(const {}).data('light');
      await tester.pumpWidget(_app(data, const MarkdownView('# One\n\nbody')));
      final region = tester.widget<SelectableRegion>(
        find.byType(SelectableRegion),
      );
      expect(
        region.selectionControls,
        same(SpringTextSelectionControls.instance),
      );
      expect(
        find.descendant(
          of: find.byType(SelectableRegion),
          matching: find.text('body', findRichText: true),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        _app(data, const MarkdownView('# One\n\nbody', selectable: false)),
      );
      expect(find.byType(SelectableRegion), findsNothing);
    });
  });

  group('MarkdownView below a DesignScope', () {
    testWidgets('its text styles by canonical name; the theme\'s where it '
        'has none', (tester) async {
      final data = SpringThemes(const {}).data('light');
      final asked = <String>{};
      final contexts = <BuildContext>{};
      TextStyle? textStyle(BuildContext context, String style) {
        asked.add(style);
        contexts.add(context);
        return switch (style) {
          'bodylarge' => const TextStyle(
            fontSize: 21,
            color: Color(0xFF123456),
            fontFamily: 'Ocean Sans',
          ),
          'headlinelarge' => const TextStyle(fontSize: 60),
          _ => null,
        };
      }

      await tester.pumpWidget(
        _app(
          data,
          DesignScope(
            textStyle: textStyle,
            selectable: (context, child) => child,
            child: const MarkdownView(_markdown, selectable: false),
          ),
        ),
      );
      expect(asked, {
        'headlinelarge',
        'headlinemedium',
        'headlinesmall',
        'titlelarge',
        'titlemedium',
        'titlesmall',
        'bodylarge',
        'bodymedium',
      });
      // Asked below the scope, where the design's theme is.
      for (final context in contexts) {
        expect(DesignScope.maybeOf(context), isNotNull);
      }
      final body = _styleOf(tester, 'body');
      expect(body.fontSize, 21);
      expect(body.color, const Color(0xFF123456));
      expect(body.fontFamily, 'Ocean Sans');
      expect(_styleOf(tester, 'One').fontSize, 60);
      // No style of the design: the SpringTheme's, with the scale's size.
      expect(_styleOf(tester, 'Two').fontSize, 28);
      expect(_styleOf(tester, 'Two').color, const Color(0xFF1D1B20));
      expect(_styleOf(tester, 'Six').fontSize, 14);
    });

    testWidgets('selectable the design\'s way, not with the starter\'s '
        'handles', (tester) async {
      final data = SpringThemes(const {}).data('light');
      var asked = 0;
      Widget selectable(BuildContext context, Widget child) {
        asked++;
        expect(DesignScope.maybeOf(context), isNotNull);
        return KeyedSubtree(
          key: const ValueKey('ocean selection'),
          child: child,
        );
      }

      Widget scope(Widget child) => _app(
        data,
        DesignScope(
          textStyle: (context, style) => null,
          selectable: selectable,
          child: child,
        ),
      );
      await tester.pumpWidget(scope(const MarkdownView('# One\n\nbody')));
      expect(asked, greaterThan(0));
      expect(find.byType(SelectableRegion), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ocean selection')),
          matching: find.text('body', findRichText: true),
        ),
        findsOneWidget,
      );

      // Text that is not selectable is not handed to the design.
      asked = 0;
      await tester.pumpWidget(
        scope(const MarkdownView('# One\n\nbody', selectable: false)),
      );
      expect(asked, 0);
      expect(find.byKey(const ValueKey('ocean selection')), findsNothing);
      expect(find.text('body', findRichText: true), findsOneWidget);
    });
  });

  group('DesignScope', () {
    TextStyle? noStyle(BuildContext context, String style) => null;
    Widget asIs(BuildContext context, Widget child) => child;

    testWidgets('maybeOf: the scope above, null in an app without a design', (
      tester,
    ) async {
      final controls = _Controls();
      late DesignScope? found;
      final probe = Builder(
        builder: (context) {
          found = DesignScope.maybeOf(context);
          return const SizedBox();
        },
      );
      await tester.pumpWidget(probe);
      expect(found, isNull);

      await tester.pumpWidget(
        DesignScope(
          textStyle: noStyle,
          selectable: asIs,
          controls: controls,
          child: probe,
        ),
      );
      expect(found!.textStyle, noStyle);
      expect(found!.selectable, asIs);
      expect(found!.controls, same(controls));

      await tester.pumpWidget(
        DesignScope(textStyle: noStyle, selectable: asIs, child: probe),
      );
      expect(found!.controls, isNull);
    });

    testWidgets('the widgets below are built again only when what it gives '
        'changes', (tester) async {
      var builds = 0;
      final dependent = Builder(
        builder: (context) {
          DesignScope.maybeOf(context);
          builds++;
          return const SizedBox();
        },
      );
      final controls = _Controls();
      Widget scope({
        TextStyle? Function(BuildContext, String)? textStyle,
        Widget Function(BuildContext, Widget)? selectable,
        DesignControls? controls,
      }) => DesignScope(
        textStyle: textStyle ?? noStyle,
        selectable: selectable ?? asIs,
        controls: controls,
        child: dependent,
      );

      await tester.pumpWidget(scope());
      expect(builds, 1);
      await tester.pumpWidget(scope());
      expect(builds, 1);
      await tester.pumpWidget(scope(textStyle: (context, style) => null));
      expect(builds, 2);
      await tester.pumpWidget(scope());
      expect(builds, 3);
      await tester.pumpWidget(scope(selectable: (context, child) => child));
      expect(builds, 4);
      await tester.pumpWidget(scope(controls: controls));
      expect(builds, 5);
      await tester.pumpWidget(scope(controls: controls));
      expect(builds, 5);
    });

    group('controlsOf', () {
      // An application whose DesignControls beans are [controls], each
      // with its order.
      Future<ApplicationContext> application(
        List<(String, _Controls, int?)> controls,
      ) async {
        final context = await SpringApplication([
          BeanModule('test', [
            for (final (name, bean, order) in controls)
              BeanDefinition<_Controls>(
                name: name,
                types: const [_Controls, DesignControls],
                order: order,
                create: (_) => bean,
              ),
          ]),
        ], bannerMode: BannerMode.off).runAsync(const []);
        addTearDown(context.close);
        return context;
      }

      // What controlsOf finds at a context below [above].
      Future<DesignControls?> controlsBelow(
        WidgetTester tester,
        Widget Function(Widget probe) above,
      ) async {
        DesignControls? found;
        await tester.pumpWidget(
          above(
            Builder(
              builder: (context) {
                found = DesignScope.controlsOf(context);
                return const SizedBox();
              },
            ),
          ),
        );
        return found;
      }

      testWidgets("the scope's controls win over every bean", (tester) async {
        final ocean = _Controls('ocean');
        final scoped = _Controls();
        final context = await application([('ocean', ocean, null)]);
        expect(
          await controlsBelow(
            tester,
            (probe) => SpringScope(
              applicationContext: context,
              child: _App(
                'ocean',
                child: DesignScope(
                  textStyle: noStyle,
                  selectable: asIs,
                  controls: scoped,
                  child: probe,
                ),
              ),
            ),
          ),
          same(scoped),
        );
        // A scope without controls: the bean that finds its app.
        expect(
          await controlsBelow(
            tester,
            (probe) => SpringScope(
              applicationContext: context,
              child: _App(
                'ocean',
                child: DesignScope(
                  textStyle: noStyle,
                  selectable: asIs,
                  child: probe,
                ),
              ),
            ),
          ),
          same(ocean),
        );
      });

      testWidgets('without a scope: the bean that finds its app above', (
        tester,
      ) async {
        final ocean = _Controls('ocean');
        final sand = _Controls('sand');
        final context = await application([
          ('ocean', ocean, null),
          ('sand', sand, null),
        ]);
        Widget under(String design, Widget probe) => SpringScope(
          applicationContext: context,
          child: _App(design, child: probe),
        );
        expect(
          await controlsBelow(tester, (probe) => under('sand', probe)),
          same(sand),
        );
        expect(
          await controlsBelow(tester, (probe) => under('ocean', probe)),
          same(ocean),
        );
      });

      testWidgets('of the beans that find their app, the first in @Order', (
        tester,
      ) async {
        final late = _Controls('ocean');
        final early = _Controls('ocean');
        final context = await application([
          ('late', late, 10),
          ('early', early, -100),
        ]);
        expect(
          await controlsBelow(
            tester,
            (probe) => SpringScope(
              applicationContext: context,
              child: _App('ocean', child: probe),
            ),
          ),
          same(early),
        );
      });

      testWidgets('none: null', (tester) async {
        // No SpringScope, no DesignScope.
        expect(await controlsBelow(tester, (probe) => probe), isNull);
        // Beans that find no app of theirs above.
        final context = await application([
          ('ocean', _Controls('ocean'), null),
          ('blind', _Controls(), null),
        ]);
        expect(
          await controlsBelow(
            tester,
            (probe) => SpringScope(
              applicationContext: context,
              child: _App(
                'sand',
                child: DesignScope(
                  textStyle: noStyle,
                  selectable: asIs,
                  child: probe,
                ),
              ),
            ),
          ),
          isNull,
        );
        // An application without DesignControls beans.
        final empty = await application(const []);
        expect(
          await controlsBelow(
            tester,
            (probe) => SpringScope(
              applicationContext: empty,
              child: _App('ocean', child: probe),
            ),
          ),
          isNull,
        );
      });
    });

    test('a text field and a button for a design to draw: their defaults', () {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final field = DesignTextField(controller: controller, label: 'User name');
      expect(field.controller, same(controller));
      expect(field.label, 'User name');
      expect(field.enabled, isTrue);
      expect(field.autofocus, isFalse);
      expect(field.obscureText, isFalse);
      expect(
        [
          field.focusNode,
          field.errorText,
          field.toggleObscured,
          field.toggleLabel,
          field.autofillHints,
          field.keyboardType,
          field.textInputAction,
          field.onSubmitted,
        ],
        everyElement(isNull),
      );

      var pressed = 0;
      final button = DesignButton(label: 'Sign in', onPressed: () => pressed++);
      button.onPressed!();
      expect(pressed, 1);
      expect(button.label, 'Sign in');
      expect(button.busy, isFalse);
      expect(button.keepsLabel, isFalse);
      expect(button.icon, isNull);
      expect(const DesignButton(label: 'x', onPressed: null).onPressed, isNull);
    });
  });
}
