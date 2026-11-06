// MarkdownView: Markdown as widgets with the theme's styles, the code
// colored by kind (CodeTokens: Dart, YAML, properties, shell, JSON), links
// handed to onLink, HTML in the Markdown shown as text, a front matter
// left out.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';

List<(String, CodeTokenKind)> _tokens(String code, String language) => [
  for (final token in CodeTokens.of(code, language))
    if (token.kind != CodeTokenKind.plain) (token.text, token.kind),
];

Widget _app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: DefaultTextStyle(
    style: const TextStyle(fontSize: 14, color: Color(0xFF000000)),
    child: child,
  ),
);

void main() {
  group('CodeTokens', () {
    test('Dart', () {
      expect(
        _tokens(
          "@Service()\nfinal class A { // one\n  var b = 'x'; int c = 42;\n}",
          'dart',
        ),
        [
          ('@Service', CodeTokenKind.annotation),
          ('()', CodeTokenKind.punctuation),
          ('final', CodeTokenKind.keyword),
          ('class', CodeTokenKind.keyword),
          ('{', CodeTokenKind.punctuation),
          ('// one', CodeTokenKind.comment),
          ('var', CodeTokenKind.keyword),
          ("'x'", CodeTokenKind.string),
          (';', CodeTokenKind.punctuation),
          ('int', CodeTokenKind.type),
          ('42', CodeTokenKind.number),
          (';', CodeTokenKind.punctuation),
          ('}', CodeTokenKind.punctuation),
        ],
      );
    });

    test('YAML', () {
      expect(
        _tokens(
          'server:\n  port: 8080 # the port\n  name: "shop"\n  ssl: false',
          'yaml',
        ),
        [
          ('server', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('port', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('8080', CodeTokenKind.number),
          ('# the port', CodeTokenKind.comment),
          ('name', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('"shop"', CodeTokenKind.string),
          ('ssl', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('false', CodeTokenKind.keyword),
        ],
      );
    });

    test('YAML: flow maps and lists, units, references, anchors', () {
      expect(
        _tokens(
          '- durations: { fast: 120ms, medium: 0.25s }\n'
              '  colors: [\$neon.accent, \$neon.cyan]\n'
              '  base: &base { alpha: 35% }\n'
              '  copy: *base\n'
              '  port: \${PORT:8080} # env\n'
              '  text: |\n'
              '  url: https://a.dev/x:1',
          'yaml',
        ),
        [
          ('-', CodeTokenKind.punctuation),
          ('durations', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('{', CodeTokenKind.punctuation),
          ('fast', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('120ms', CodeTokenKind.number),
          (',', CodeTokenKind.punctuation),
          ('medium', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('0.25s', CodeTokenKind.number),
          ('}', CodeTokenKind.punctuation),
          ('colors', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('[', CodeTokenKind.punctuation),
          (r'$neon.accent', CodeTokenKind.variable),
          (',', CodeTokenKind.punctuation),
          (r'$neon.cyan', CodeTokenKind.variable),
          (']', CodeTokenKind.punctuation),
          ('base', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('&base', CodeTokenKind.variable),
          ('{', CodeTokenKind.punctuation),
          ('alpha', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('35%', CodeTokenKind.number),
          ('}', CodeTokenKind.punctuation),
          ('copy', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('*base', CodeTokenKind.variable),
          ('port', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          (r'${PORT:8080}', CodeTokenKind.variable),
          ('# env', CodeTokenKind.comment),
          ('text', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('|', CodeTokenKind.punctuation),
          ('url', CodeTokenKind.key),
          (':', CodeTokenKind.punctuation),
          ('https://a.dev/x:1', CodeTokenKind.string),
        ],
      );
    });

    test('YAML and properties: a value without quotes is a string', () {
      expect(_tokens('curve: ease-out\nb: { c: linear }', 'yaml'), [
        ('curve', CodeTokenKind.key),
        (':', CodeTokenKind.punctuation),
        ('ease-out', CodeTokenKind.string),
        ('b', CodeTokenKind.key),
        (':', CodeTokenKind.punctuation),
        ('{', CodeTokenKind.punctuation),
        ('c', CodeTokenKind.key),
        (':', CodeTokenKind.punctuation),
        ('linear', CodeTokenKind.string),
        ('}', CodeTokenKind.punctuation),
      ]);
      expect(_tokens('a.b=on-time', 'properties'), [
        ('a.b', CodeTokenKind.key),
        ('=', CodeTokenKind.punctuation),
        ('on-time', CodeTokenKind.string),
      ]);
    });

    test('YAML: a flow collection over several lines', () {
      expect(_tokens('a: [\n  b: 1,\n  2 ]', 'yaml'), [
        ('a', CodeTokenKind.key),
        (':', CodeTokenKind.punctuation),
        ('[', CodeTokenKind.punctuation),
        ('b', CodeTokenKind.key),
        (':', CodeTokenKind.punctuation),
        ('1', CodeTokenKind.number),
        (',', CodeTokenKind.punctuation),
        ('2', CodeTokenKind.number),
        (']', CodeTokenKind.punctuation),
      ]);
    });

    test('Dart: types and punctuation', () {
      expect(_tokens('int a = 1;', 'dart').first, ('int', CodeTokenKind.type));
      expect(_tokens('final a = <String>[];', 'dart'), [
        ('final', CodeTokenKind.keyword),
        ('String', CodeTokenKind.type),
        ('[];', CodeTokenKind.punctuation),
      ]);
    });

    test('shell and JSON', () {
      expect(_tokens(r'echo $HOME && ls', 'sh'), [
        ('echo', CodeTokenKind.keyword),
        (r'$HOME', CodeTokenKind.variable),
        ('&&', CodeTokenKind.punctuation),
      ]);
      expect(_tokens('{"a": [1]}', 'json'), [
        ('{', CodeTokenKind.punctuation),
        ('"a"', CodeTokenKind.key),
        (':', CodeTokenKind.punctuation),
        ('[', CodeTokenKind.punctuation),
        ('1', CodeTokenKind.number),
        (']}', CodeTokenKind.punctuation),
      ]);
    });

    test('properties', () {
      expect(_tokens('# c\nserver.port=8080', 'properties'), [
        ('# c', CodeTokenKind.comment),
        ('server.port', CodeTokenKind.key),
        ('=', CodeTokenKind.punctuation),
        ('8080', CodeTokenKind.number),
      ]);
    });

    test('the pieces join to the code', () {
      const code = "a: 'b' # c\n- d: [1, 2]";
      expect(CodeTokens.of(code, 'yaml').map((t) => t.text).join(), code);
      expect(CodeTokens.of(code, 'cobol').single.kind, CodeTokenKind.plain);
      for (final (text, language) in [
        ("a: { b: [1, 'x', \"y\"], c: \${d:e} } # f\n- - g: &h *i", 'yaml'),
        ("k: 'it''s'\nl: \"\\\"\"\nm: [\n  n,\n  { o: p }\n]\n---\n", 'yaml'),
        ('q: |\n  r: s\n  t\nu: !tag v', 'yaml'),
        (r'a=${b:c},d  # e', 'properties'),
        (r'echo "$A" | grep -v ${B}; ls', 'sh'),
        ("final f = <A<B>>{'k': [1, 2.5e3]}; // c", 'dart'),
      ]) {
        expect(
          CodeTokens.of(text, language).map((t) => t.text).join(),
          text,
          reason: text,
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

  testWidgets("in a SpringTheme: headings in Theme.of's sizes, code in "
      'styles.code', (tester) async {
    final themes = SpringThemes(const {
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
            '# Big\n\nbody\n\n```dart\nfinal a = 1;\n```\n',
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
        if (span is TextSpan && span.text == 'final') {
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
    tester.widget<RichText>(find.byType(RichText)).text.visitChildren((span) {
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
}
