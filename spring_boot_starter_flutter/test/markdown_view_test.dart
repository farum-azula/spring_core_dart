// MarkdownView: Markdown as widgets with the theme's styles, the code
// colored by the theme's languages (syntax.<name>, CodeSyntax), links
// handed to onLink, HTML in the Markdown shown as text, a front matter
// left out.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

List<(String, CodeTokenKind)> _pieces(List<CodeToken> tokens) => [
  for (final token in tokens)
    if (token.kind != CodeTokenKind.plain && token.text.trim().isNotEmpty)
      (token.text, token.kind),
];

const _java = {
  'syntax.java.aliases': 'jav',
  'syntax.java.keywords': 'public, long, int, return',
  'syntax.java.types': '^[A-Z][A-Za-z0-9_]*[a-z]',
  'syntax.java.rules.0.match': r'//[^\n]*',
  'syntax.java.rules.0.kind': 'comment',
  'syntax.java.rules.1.match': r'"(?:\\.|[^"\\\n])*"',
  'syntax.java.rules.1.kind': 'string',
  'syntax.java.rules.2.match': r'@[A-Za-z_][\w.]*',
  'syntax.java.rules.2.kind': 'annotation',
  'syntax.java.rules.3.match': r'[A-Za-z_$][\w$]*',
  'syntax.java.rules.3.kind': 'word',
  'syntax.java.rules.4.match': r'[{}()\[\];,]',
  'syntax.java.rules.4.kind': 'punctuation',
};

CodeSyntax? _syntax(Map<String, String> values, String language) =>
    SpringThemes(values).data('light').syntaxOf(language);

Widget _app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
    child: child,
  ),
);

void main() {
  group('the languages of the theme (syntax)', () {
    test('rules in order, words by keywords and types, neighbors joined', () {
      final java = _syntax(_java, 'java')!;
      expect(
        _pieces(java.tokens('@Bean public Store store(long n) { // one\n}')),
        [
          ('@Bean', CodeTokenKind.annotation),
          ('public', CodeTokenKind.keyword),
          ('Store', CodeTokenKind.type),
          ('(', CodeTokenKind.punctuation),
          ('long', CodeTokenKind.keyword),
          (')', CodeTokenKind.punctuation),
          ('{', CodeTokenKind.punctuation),
          ('// one', CodeTokenKind.comment),
          ('}', CodeTokenKind.punctuation),
        ],
      );
      const code = 'String s = "a\\"b"; // c\nint n = 42;';
      expect(java.tokens(code).map((t) => t.text).join(), code);
    });

    test('a language by its name or an alias, in any case', () {
      final themes = SpringThemes(_java);
      final data = themes.data('light');
      expect(data.syntaxOf('java'), isNotNull);
      expect(data.syntaxOf('JAV'), same(data.syntaxOf('java')));
      expect(data.syntaxOf('cobol'), isNull);
      expect(data.syntaxOf(null), isNull);
    });

    test('no language: one plain piece', () {
      expect(CodeTokens.of('a b', null), [
        (text: 'a b', kind: CodeTokenKind.plain),
      ]);
    });

    test(r'the rules are taken as written: no $ reference, no $$', () {
      final syntax = _syntax({
        'syntax.shell.rules.0.match': r'\$[A-Za-z_]\w*|\$\$',
        'syntax.shell.rules.0.kind': 'variable',
      }, 'shell')!;
      expect(_pieces(syntax.tokens(r'echo $HOME $$')), [
        (r'$HOME', CodeTokenKind.variable),
        (r'$$', CodeTokenKind.variable),
      ]);
    });

    test('^ and \$ are a line\'s start and end', () {
      final syntax = _syntax({
        'syntax.ini.rules.0.match': r'^[a-z]+(?==)',
        'syntax.ini.rules.0.kind': 'key',
      }, 'ini')!;
      expect(_pieces(syntax.tokens('a=1\nbc=2')), [
        ('a', CodeTokenKind.key),
        ('bc', CodeTokenKind.key),
      ]);
    });

    test('a wrong language stops the start and names the property', () {
      for (final (values, problem) in [
        (
          {'syntax.x.rules.0.match': 'a', 'syntax.x.rules.0.kind': 'color'},
          'a kind',
        ),
        (
          {'syntax.x.rules.0.match': '(', 'syntax.x.rules.0.kind': 'string'},
          'a regular expression',
        ),
        ({'syntax.x.rules.0.kind': 'string'}, 'a regular expression'),
        ({'syntax.x.keywords': 'a'}, 'a list of rules'),
        (
          {
            'syntax.x.rules.0.match': 'a',
            'syntax.x.rules.0.kind': 'string',
            'syntax.x.colors': 'red',
          },
          'a key of a language',
        ),
        (
          {
            'syntax.x.types': '(',
            'syntax.x.rules.0.match': 'a',
            'syntax.x.rules.0.kind': 'word',
          },
          'a regular expression',
        ),
      ]) {
        expect(
          () => SpringThemes(values).data('light'),
          throwsA(
            isA<ThemePropertyException>().having(
              (e) => e.toString(),
              'message',
              allOf(
                contains('spring.flutter.theme.syntax.x'),
                contains(problem),
              ),
            ),
          ),
          reason: '$values',
        );
      }
    });
  });

  testWidgets('headings, text, code and links', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      _app(
        MarkdownView(
          '---\ntitle: Hidden\n---\n'
          '# Beans\n\nA **bean** and `code`, see [scopes](scopes.md#a).\n\n'
          '```yaml\nserver:\n  port: 8080\n```\n\n'
          '- one\n- two\n\n'
          '<b>not bold</b>\n',
          onLink: tapped.add,
          selectable: false,
        ),
      ),
    );
    expect(find.text('Beans'), findsOneWidget);
    expect(find.textContaining('Hidden'), findsNothing);
    expect(find.textContaining('A bean and code, see scopes.'), findsOneWidget);
    expect(
      find.textContaining('port: 8080', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('one'), findsOneWidget);
    expect(find.text('<b>not bold</b>'), findsOneWidget);

    await tester.tapOnText(find.textRange.ofSubstring('scopes'));
    expect(tapped, ['scopes.md#a']);
  });
  testWidgets('a line break in a paragraph is a space; two spaces break', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MarkdownView(
          'one\ntwo `a\nb`\n\nthree  \nfour\n',
          selectable: false,
        ),
      ),
    );
    expect(find.text('one two a b'), findsOneWidget);
    expect(find.text('three\nfour'), findsOneWidget);
  });

  testWidgets('code blocks show < > & as written', (tester) async {
    await tester.pumpWidget(
      _app(
        const MarkdownView(
          "```dart\nfinal a = <String>['x' && 'y'];\nint f() => 1;\n```\n",
          selectable: false,
        ),
      ),
    );
    expect(
      find.textContaining(
        "final a = <String>['x' && 'y'];\nint f() => 1;",
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a wide table scrolls sideways; a column wraps at cell-width', (
    tester,
  ) async {
    final data = SpringThemes({'styles.table.cell-width': '150'}).data('light');
    final long = 'a long text that wraps inside its column ' * 3;
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => Center(
          child: SizedBox(
            width: 320,
            child: SpringTheme(
              data: data,
              child: MarkdownView(
                '| A | B | C |\n|---|---|---|\n| $long | $long | $long |',
                selectable: false,
              ),
            ),
          ),
        ),
      ),
    );
    final table = tester.getSize(find.byType(Table));
    expect(table.width, greaterThan(320), reason: 'not squeezed');
    expect(table.width, lessThanOrEqualTo(3 * 150 + 4));
    final scroll = tester.widget<SingleChildScrollView>(
      find.ancestor(
        of: find.byType(Table),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroll.scrollDirection, Axis.horizontal);
    final start = tester.getTopLeft(find.byType(Table)).dx;
    await tester.drag(find.byType(Table), const Offset(-200, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byType(Table)).dx, lessThan(start));
  });

  testWidgets('a narrow table fills the width; fill: false keeps it narrow', (
    tester,
  ) async {
    Future<double> width(Map<String, String> properties) async {
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          builder: (context, _) => Center(
            child: SizedBox(
              width: 600,
              child: SpringTheme(
                data: SpringThemes(properties).data('light'),
                child: const MarkdownView(
                  '| A | B |\n|---|---|\n| one | two |',
                  selectable: false,
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(Table)).width;
    }

    expect(await width({}), 600);
    expect(await width({'styles.table.fill': 'false'}), lessThan(200));
  });

  testWidgets('a heading breaks a long identifier after an underscore', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const MarkdownView('# spring_boot_starter', selectable: false)),
    );
    final text = tester
        .widget<RichText>(find.byType(RichText).first)
        .text
        .toPlainText();
    expect(text, 'spring_\u200Bboot_\u200Bstarter');
  });

  testWidgets('styles.heading: a color for every level, h2 its own', (
    tester,
  ) async {
    final data = SpringThemes({
      'styles.heading.color': '#112233',
      'styles.heading.h2': '#445566',
    }).data('light');
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => SpringTheme(
          data: data,
          child: const MarkdownView(
            '# One\n\n## Two\n\ntext',
            selectable: false,
          ),
        ),
      ),
    );
    Color? colorOf(String text) => tester
        .widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == text,
          ),
        )
        .text
        .style
        ?.color;
    expect(colorOf('One'), const Color(0xFF112233));
    expect(colorOf('Two'), const Color(0xFF445566));
    expect(colorOf('text'), isNot(const Color(0xFF112233)));
  });

  testWidgets('in a WidgetsApp, a dark theme: the text in its colors', (
    tester,
  ) async {
    final data = SpringThemes({
      'themes.night.brightness': 'dark',
    }).data('night');
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => SpringTheme(
          data: data,
          child: const MarkdownView('# Big\n\nbody', selectable: false),
        ),
      ),
    );
    Color? colorOf(String text) => tester
        .widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == text,
          ),
        )
        .text
        .style
        ?.color;
    // Not Material's light fallback: the dark theme's light text.
    expect(colorOf('body'), data.toMaterial().textTheme.bodyLarge!.color);
    expect(colorOf('body')!.computeLuminance(), greaterThan(0.5));
    expect(colorOf('Big')!.computeLuminance(), greaterThan(0.5));
    // The sizes of Material's typography, as Theme.of would give them.
    double? sizeOf(String text) => tester
        .widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == text,
          ),
        )
        .text
        .style
        ?.fontSize;
    expect(sizeOf('Big'), greaterThan(sizeOf('body')! * 1.5));
  });

  testWidgets("in a SpringTheme: headings in Theme.of's sizes, code in "
      'styles.code', (tester) async {
    final themes = SpringThemes({
      ..._java,
      'syntax.java.aliases': 'jav, dart',
      'styles.code.keyword': '#123456',
      'styles.code.background': '#ABCDEF',
      'styles.code.radius': '10',
      'styles.code.padding.0': '4',
      'styles.code.padding.1': '2',
      'styles.code.border': '#FF0000',
      'styles.code.border-width': '2',
    });
    final data = themes.data('light');
    await tester.pumpWidget(
      MaterialApp(
        theme: data.toMaterial(),
        home: SpringTheme(
          data: data,
          child: const MarkdownView(
            '# Big\n\nbody\n\n```dart\npublic a = 1;\n```\n',
            selectable: false,
          ),
        ),
      ),
    );
    final text = Theme.of(tester.element(find.byType(MarkdownView))).textTheme;
    final heading = tester.widget<RichText>(
      find.descendant(
        of: find.byType(MarkdownView),
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == 'Big',
        ),
      ),
    );
    expect(heading.text.style?.fontSize, text.headlineLarge!.fontSize);
    expect(
      heading.text.style?.fontSize,
      greaterThan(text.bodyLarge!.fontSize!),
    );

    Color? keyword;
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'public') {
          keyword = span.style?.color;
        }
        return keyword == null;
      });
    }
    expect(keyword, const Color(0xFF123456));
    final block = tester.widget<Container>(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            (w.decoration as BoxDecoration?)?.color == const Color(0xFFABCDEF),
      ),
    );
    final decoration = block.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(10));
    expect(
      decoration.border,
      Border.all(color: const Color(0xFFFF0000), width: 2),
    );
    expect(
      block.padding,
      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  });

  testWidgets('MarkdownView.code: one block, backticks in the code kept', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        MarkdownView.code(
          'a: "```"\nb: 1 # c',
          language: 'yaml',
          selectable: false,
        ),
      ),
    );
    final spans = <(String, Color?)>[];
    // The code; the copy button's icon is a RichText too.
    tester.widget<RichText>(find.byType(RichText).first).text.visitChildren((
      span,
    ) {
      if (span is TextSpan && span.text != null) {
        spans.add((span.text!, span.style?.color));
      }
      return true;
    });
    expect(spans.map((s) => s.$1).join(), 'a: "```"\nb: 1 # c');
  });

  testWidgets('selectable without MaterialLocalizations (a CupertinoApp)', (
    tester,
  ) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
        home: const MarkdownView('# Title\n\ntext'),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(SelectableRegion), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('no gap after the last block: a lone code block is the view', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Align(
          alignment: Alignment.topLeft,
          child: MarkdownView('```yaml\na: b\n```\n', selectable: false),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(MarkdownView)).height,
      tester.getSize(find.byType(Container)).height,
    );
  });

  group('documentation pieces', () {
    // The color of the span that reads [text] (a link's color is on the
    // span around its pieces).
    Color? colorOf(WidgetTester tester, String text) {
      Color? find_(InlineSpan span) {
        if (span is! TextSpan) {
          return null;
        }
        if (span.toPlainText() == text && span.style?.color != null) {
          return span.style!.color;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          final found = find_(child);
          if (found != null) {
            return found;
          }
        }
        return null;
      }

      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        final found = find_(rich.text);
        if (found != null) {
          return found;
        }
      }
      return null;
    }

    Future<void> pumpThemed(
      WidgetTester tester,
      Map<String, String> theme,
      String markdown,
    ) {
      final data = SpringThemes(theme).data('light');
      return tester.pumpWidget(
        MaterialApp(
          theme: data.toMaterial(),
          home: SpringTheme(
            data: data,
            child: MarkdownView(markdown, selectable: false),
          ),
        ),
      );
    }

    testWidgets('a callout: its kind as a title, in styles.callout', (
      tester,
    ) async {
      await pumpThemed(tester, const {
        'styles.callout.warning': '#AA0000',
      }, '> [!WARNING]\n> Checked at startup.\n');
      expect(find.text('WARNING'), findsOneWidget);
      expect(find.text('Checked at startup.'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('WARNING')).style?.color,
        const Color(0xFFAA0000),
      );
    });

    testWidgets('a titled code block: its title and a copy button', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpThemed(
        tester,
        const {'styles.code.title': '#00AA00'},
        '```dart title="lib/main.dart"\nvoid main() {}\n```\n\n```dart\nuntitled\n```\n',
      );
      expect(find.text('lib/main.dart'), findsOneWidget);
      // Every block has one: the titled in its header, the other in its
      // corner.
      expect(find.byIcon(Icons.copy_rounded), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.copy_rounded).first);
      await tester.pump();
      expect(copied, 'void main() {}');
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.copy_rounded));
      await tester.pump();
      expect(copied, 'untitled');
      // The untitled block is as wide as the titled one, the button in its
      // corner.
      final blocks = find.ancestor(
        of: find.text('untitled', findRichText: true),
        matching: find.byType(Stack),
      );
      expect(
        tester.getSize(blocks.first).width,
        tester.getSize(find.byType(MarkdownView)).width,
      );
      expect(
        tester.widget<Text>(find.text('lib/main.dart')).style?.color,
        const Color(0xFF00AA00),
      );
    });

    testWidgets('styles.code.copy: false, no copy buttons', (tester) async {
      await pumpThemed(
        tester,
        const {'styles.code.copy': 'false'},
        '```dart title="a.dart"\na\n```\n\n```dart\nb\n```\n',
      );
      expect(find.byIcon(Icons.copy_rounded), findsNothing);
    });

    testWidgets('themes=: a button per palette switches the colors', (
      tester,
    ) async {
      await pumpThemed(tester, const {
        ..._java,
        'styles.code.keyword': '#000001',
        'styles.code-night.label': 'Night',
        'styles.code-night.keyword': '#112233',
        'styles.code-day.keyword': '#445566',
      }, '```java themes="night day missing"\npublic int x;\n```\n');
      // A palette the theme does not have is left out.
      expect(find.text('Night'), findsOneWidget);
      expect(find.text('day'), findsOneWidget);
      expect(find.text('missing'), findsNothing);
      expect(colorOf(tester, 'public'), const Color(0xFF112233));
      await tester.tap(find.text('day'));
      await tester.pump();
      expect(colorOf(tester, 'public'), const Color(0xFF445566));
    });

    testWidgets('inline code and links in their own colors', (tester) async {
      await pumpThemed(tester, const {
        'styles.code.inline-text': '#112233',
        'styles.link.color': '#445566',
      }, 'Use `@Bean()` and [the docs](x.md).');
      expect(colorOf(tester, '@Bean()'), const Color(0xFF112233));
      expect(colorOf(tester, 'the docs'), const Color(0xFF445566));
    });

    testWidgets("a resource in the app's language", (tester) async {
      final context = await SpringApplication([
        BeanModule(
          'test',
          const [],
          resources: {
            'content/a.md': const EmbeddedResource.text('# English\n'),
            'content/a.ja.md': const EmbeddedResource.text('# 日本語\n'),
          },
        ),
      ], bannerMode: BannerMode.off).runAsync(const []);
      addTearDown(context.close);
      Widget at(Locale locale) => SpringScope(
        applicationContext: context,
        child: Localizations(
          locale: locale,
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: MarkdownView.resource(
              'resources:content/a.md',
              selectable: false,
            ),
          ),
        ),
      );
      await tester.pumpWidget(at(const Locale('en')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('English'), findsOneWidget);
      await tester.pumpWidget(at(const Locale('ja')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(find.text('日本語'), findsOneWidget);
    });
  });

  testWidgets('the outline: headings with their anchors, #links scroll', (
    tester,
  ) async {
    final outline = MarkdownOutline();
    addTearDown(outline.dispose);
    var notified = 0;
    outline.addListener(() => notified++);
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: MarkdownView(
            '# Beans\n\nSee [the methods](#bean-methods).\n\n'
            '${'text\n\n' * 60}'
            '## `@Bean()` methods\n\n## Why\n\n## Why\n',
            outline: outline,
            selectable: false,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(notified, 1);
    expect(
      [for (final h in outline.headings) '${h.level} ${h.text} #${h.id}'],
      [
        '1 Beans #beans',
        '2 @Bean() methods #bean-methods',
        '2 Why #why',
        '2 Why #why-1',
      ],
    );
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, 0);
    await tester.tapOnText(find.textRange.ofSubstring('the methods'));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    expect(outline.show('nowhere'), isFalse);
  });

  testWidgets('a long page comes in over frames; show builds the rest', (
    tester,
  ) async {
    final outline = MarkdownOutline();
    addTearDown(outline.dispose);
    final paragraph = 'word ' * 100;
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: MarkdownView(
            '# Top\n\n${'$paragraph\n\n' * 200}## Bottom\n\nThe end.\n',
            outline: outline,
            selectable: false,
          ),
        ),
      ),
    );
    // The first frame has the top of the page, not the whole of it.
    expect(find.text('Top'), findsOneWidget);
    expect(find.text('Bottom', skipOffstage: false), findsNothing);
    await tester.pump();
    // A heading not built yet: the page is built, then scrolled to it.
    expect(outline.show('bottom'), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('The end.'), findsOneWidget);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, greaterThan(0));
  });

  testWidgets('a long page is whole after a few frames', (tester) async {
    await tester.pumpWidget(
      _app(
        SingleChildScrollView(
          child: MarkdownView(
            '# Top\n\n${'${'word ' * 100}\n\n' * 200}The end.\n',
            selectable: false,
          ),
        ),
      ),
    );
    expect(find.text('The end.', skipOffstage: false), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('The end.', skipOffstage: false), findsOneWidget);
  });

  testWidgets(
    '{{key}} placeholders with spring.flutter.markdown.placeholders',
    (
      tester,
    ) async {
      Future<ApplicationContext> start(String properties) async {
        final context = await SpringApplication([
          BeanModule(
            'test',
            const [],
            resources: {
              'application.properties': EmbeddedResource.text(
                'site.package-version=0.7.2\n$properties',
              ),
            },
          ),
        ], bannerMode: BannerMode.off).runAsync(const []);
        addTearDown(context.close);
        return context;
      }

      Widget view(ApplicationContext context) => SpringScope(
        applicationContext: context,
        child: _app(
          const MarkdownView(
            'Version ^{{site.package-version}}, {{baseUrl}}, \\{{x}}.',
            selectable: false,
          ),
        ),
      );
      await tester.pumpWidget(
        view(await start('spring.flutter.markdown.placeholders=true')),
      );
      expect(find.text('Version ^0.7.2, {{baseUrl}}, {{x}}.'), findsOneWidget);
      // Off by default: the text as it is (Markdown makes `\{` a `{`).
      await tester.pumpWidget(view(await start('')));
      expect(
        find.text('Version ^{{site.package-version}}, {{baseUrl}}, {{x}}.'),
        findsOneWidget,
      );
    },
  );
}
