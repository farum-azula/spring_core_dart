// Markdown pages as documents: the title, one document per section with
// GitHub's anchor, plain text, links from the file's path, translations
// next to the file and the pages without one.
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/spring_search_dart.dart';
import 'package:test/test.dart';

const _page = '''
---
title: "The container"
description: skipped
---

# Ignored when the front matter has a title

Opening text with a [link](other.md) and `code`.

## Why beans?

> [!NOTE]
> A **note**.

```dart
## not a heading
final bean = Bean();
```

## Why beans?

| a | b |
|---|---|
| 1 | 2 |
''';

void main() {
  test('a page in sections, with anchors and plain text', () {
    final page = MarkdownSections.parse(_page);
    expect(page.title, 'The container');
    expect(
      [for (final s in page.sections) s.heading],
      ['', 'Why beans?', 'Why beans?'],
    );
    expect(
      [for (final s in page.sections) s.anchor],
      [null, 'why-beans', 'why-beans-1'],
    );
    expect(page.sections[0].body, 'Opening text with a link and code.');
    expect(
      page.sections[1].body,
      'A note. ## not a heading final bean = Bean();',
    );
    expect(page.sections[2].body, 'a b 1 2');
    expect(MarkdownSections.parse('# Title\n\ntext').title, 'Title');
  });

  group('the files of a location', () {
    setUpAll(() {
      Resources.registerAll(const {
        'docs/index.md': EmbeddedResource.text('# Home\n\nWelcome.'),
        'docs/index.ja.md': EmbeddedResource.text('# ホーム\n\nようこそ。'),
        'docs/beans/component.md': EmbeddedResource.text(
          '# @Component\n\nA bean.\n\n## Scan\n\nFound by the scan.',
        ),
        'docs/contents.md': EmbeddedResource.text('# Contents'),
      });
    });

    Future<List<SearchDocument>> documents() => MarkdownSearchSource(
      PathMatchingResourcePatternResolver(),
      location: 'resources:docs/**/*.md',
      exclude: ['**/contents*.md', 'contents*.md'],
      link: '/guide/{path}',
    ).documents().toList();

    test('links from the path, sections with anchors, attributes', () async {
      final english = [
        for (final d in await documents())
          if (d.language == 'en') d,
      ];
      expect(
        [for (final d in english) d.link],
        unorderedEquals([
          '/guide',
          '/guide/beans/component',
          '/guide/beans/component#scan',
        ]),
      );
      final scan = english.firstWhere((d) => d.link!.endsWith('#scan'));
      expect(scan.fields, {
        'title': '@Component',
        'heading': 'Scan',
        'body': 'Found by the scan.',
      });
      expect(scan.attributes, {
        'page': '/guide/beans/component',
        'section': 'Scan',
        'path': 'docs/beans/component.md',
      });
    });

    test(
      'a translation next to the file; a page without one in its own',
      () async {
        final japanese = [
          for (final d in await documents())
            if (d.language == 'ja') d,
        ];
        expect(
          {for (final d in japanese) d.link: d.title},
          {
            '/guide': 'ホーム',
            '/guide/beans/component': '@Component',
            '/guide/beans/component#scan': '@Component',
          },
        );
      },
    );
  });
}
