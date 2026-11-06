// The site's pages (spring.flutter.web.seo.*): a page per route and per
// Markdown file, each a copy of web/index.html with its head and its text
// in <main>, the root page in web/index.html between markers; links between
// Markdown files become the site's addresses; sitemap.xml, robots.txt,
// llms.txt, llms-full.txt and the .md copies; pages gone are deleted.
import 'dart:convert';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/seo_builder.dart';
import 'package:test/test.dart';

const _index = r'''
<!DOCTYPE html>
<html>
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta name="description" content="A new Flutter project.">
  <title>app</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

final class _Memory implements SeoFiles {
  _Memory(this.files);

  final Map<String, String> files;

  @override
  Future<String?> read(
    BuildStep buildStep,
    String package,
    String path,
  ) async => files[path];

  @override
  Future<void> write(
    BuildStep buildStep,
    String package,
    String path,
    String content,
  ) async => files[path] = content;

  @override
  Future<void> delete(BuildStep buildStep, String package, String path) async =>
      files.remove(path);
}

const _config = '''
spring:
  flutter:
    web:
      seo:
        enabled: true
        site-url: https://spring-dart.dev
        from-routes: true
        title: '{title} · Spring Dart'
        description: Spring for Dart and Flutter.
        pages:
          - path: /
            title: Spring Dart
            description: Spring Boot for Dart servers and Flutter apps.
''';

const _configuration = '''
---
title: Configuration
description: How Spring Dart reads application.yml.
---

# Configuration

See [beans](beans.md#scopes) and [the index](../index.md).

```yaml
server:
  port: 8080
```
''';

const _beans = '''
# Beans

Beans <b>and</b> scopes.

<script>alert(1)</script>
''';

const _docsIndex = '''
# Docs

Start with [configuration](core/configuration.md).
''';

final String _routes = jsonEncode({
  'routes': [
    {'path': '/', 'name': 'home', 'class': 'HomePage', 'title': 'Home'},
    {
      'path': '/docs/{*path}',
      'name': 'doc',
      'class': 'DocPage',
      'content': 'resources:content/docs/',
    },
    {
      'path': '/account',
      'name': 'account',
      'class': 'AccountPage',
      'title': 'Account',
      'preAuthorize': 'isAuthenticated()',
    },
    {
      'path': '/books/{isbn}',
      'name': 'book',
      'class': 'BookPage',
      'title': 'Book',
      'paths': ['/books/978-0'],
    },
  ],
});

Future<List<String>> _build(
  _Memory files,
  Map<String, String> resources, {
  String? metadata,
}) async {
  final logs = <String>[];
  await testBuilder(
    SeoBuilder(files: files),
    {
      'app|pubspec.yaml': 'name: app\n',
      'app|lib/spring_gen/spring_metadata.json': ?metadata,
      for (final MapEntry(:key, :value) in resources.entries)
        'app|lib/resources/$key': value,
    },
    rootPackage: 'app',
    onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
  );
  return logs;
}

Map<String, String> _site() => {
  'application.yml': _config,
  'content/docs/index.md': _docsIndex,
  'content/docs/core/configuration.md': _configuration,
  'content/docs/core/beans.md': _beans,
};

void main() {
  test('a page per route and Markdown file, with its head and text', () async {
    final files = _Memory({'web/index.html': _index});
    final logs = await _build(files, _site(), metadata: _routes);
    expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);

    final page = files.files['web/docs/core/configuration/index.html']!;
    expect(page, contains('<base href="/">'));
    expect(page, isNot(contains('A new Flutter project.')));
    expect('<meta name="description"'.allMatches(page), hasLength(1));
    expect(page, contains('<title>Configuration · Spring Dart</title>'));
    expect(
      page,
      contains(
        '<meta name="description" content="How Spring Dart reads '
        'application.yml.">',
      ),
    );
    expect(
      page,
      contains(
        '<link rel="canonical" '
        'href="https://spring-dart.dev/docs/core/configuration">',
      ),
    );
    expect(
      page,
      contains(
        'href="https://spring-dart.dev/docs/core/configuration.md"',
      ),
    );
    expect(page, contains('<main id="spring-content"'));
    expect(page, contains('<h1 id="configuration">Configuration</h1>'));
    // Links between files: the site's addresses.
    expect(page, contains('<a href="/docs/core/beans#scopes">beans</a>'));
    expect(page, contains('<a href="/docs">the index</a>'));
    expect(page, contains('<code class="language-yaml">'));
    // The bootstrap stays after the text.
    expect(
      page.indexOf('<main'),
      lessThan(page.indexOf('flutter_bootstrap.js')),
    );

    // HTML in Markdown is text, not markup.
    final beans = files.files['web/docs/core/beans/index.html']!;
    expect(beans, contains('Beans &lt;b&gt;and&lt;/b&gt; scopes.'));
    expect(beans, contains('&lt;script&gt;alert(1)&lt;/script&gt;'));
    expect(beans, isNot(contains('<script>alert')));
    expect(
      files.files['web/docs/index.html'],
      contains('<h1 id="docs">Docs</h1>'),
    );

    // The root page: web/index.html itself, between markers.
    final root = files.files['web/index.html']!;
    expect(root, contains(r'<base href="$FLUTTER_BASE_HREF">'));
    expect(root, contains('<title>Spring Dart · Spring Dart</title>'));
    expect(root, contains('<!-- spring:seo:head:start -->'));
    expect(
      root,
      contains('content="Spring Boot for Dart servers and Flutter apps."'),
    );

    // A guarded screen: a page, but noindex and out of the sitemap.
    expect(
      files.files['web/account/index.html'],
      contains('<meta name="robots" content="noindex">'),
    );
    // A screen with variables: the addresses its RouteInfo lists.
    expect(files.files, contains('web/books/978-0/index.html'));
  });

  test('the sitemap, robots.txt, llms.txt and the Markdown copies', () async {
    final files = _Memory({'web/index.html': _index});
    await _build(files, _site(), metadata: _routes);
    final sitemap = files.files['web/sitemap.xml']!;
    expect(
      sitemap,
      contains('<loc>https://spring-dart.dev/docs/core/beans</loc>'),
    );
    expect(sitemap, isNot(contains('/account')));
    expect(
      files.files['web/robots.txt'],
      contains('Sitemap: https://spring-dart.dev/sitemap.xml'),
    );
    expect(
      files.files['web/llms.txt'],
      allOf(
        startsWith('# Spring Dart\n\n> Spring Boot for Dart servers'),
        contains(
          [
            '- [Configuration]',
            '(https://spring-dart.dev/docs/core/configuration.md)',
            ': How Spring Dart reads application.yml.',
          ].join(),
        ),
      ),
    );
    expect(files.files['web/llms-full.txt'], contains('# Beans'));
    expect(
      files.files['web/docs/core/configuration.md'],
      startsWith('\n# Configuration'),
    );
  });

  test('a link to no page fails the build', () async {
    final files = _Memory({'web/index.html': _index});
    final logs = await _build(files, {
      ..._site(),
      'content/docs/core/beans.md': 'See [gone](gone.md).',
    }, metadata: _routes);
    expect(
      logs,
      contains(allOf(startsWith('SEVERE'), contains('gone.md'))),
    );
  });

  test('pages gone are deleted, and the root page cleaned', () async {
    final files = _Memory({'web/index.html': _index});
    await _build(files, _site(), metadata: _routes);
    expect(files.files, contains('web/docs/core/beans/index.html'));
    await _build(
      files,
      {'application.yml': 'spring.application.name: app'},
      metadata: _routes,
    );
    expect(files.files.keys, ['web/index.html']);
    expect(files.files['web/index.html'], isNot(contains('spring:seo')));
  });

  test('a second build changes nothing', () async {
    final files = _Memory({'web/index.html': _index});
    await _build(files, _site(), metadata: _routes);
    final first = Map.of(files.files);
    await _build(files, _site(), metadata: _routes);
    expect(files.files, first);
  });

  test('without a site URL the build fails', () async {
    final files = _Memory({'web/index.html': _index});
    final logs = await _build(files, {
      'application.yml': 'spring.flutter.web.seo.enabled: true',
    });
    expect(logs, contains(allOf(startsWith('SEVERE'), contains('site-url'))));
  });

  test('content folders of the configuration, without routes', () async {
    final files = _Memory({'web/index.html': _index});
    await _build(files, {
      'application.yml': '''
spring.flutter.web.seo:
  enabled: true
  site-url: https://example.dev/app/
  content:
    - location: resources:blog/
      path: /blog
      exclude: ['_*.md']
''',
      'blog/first.md': '# First',
      'blog/_draft.md': '# Draft',
    });
    expect(
      files.files['web/blog/first/index.html'],
      allOf(
        contains('<base href="/app/">'),
        contains('href="https://example.dev/app/blog/first"'),
      ),
    );
    expect(files.files, isNot(contains('web/blog/_draft/index.html')));
  });

  // spring.flutter.navigation.languages: [en, ja]: a page per language,
  // `/ja/...`, the Markdown of `<file>.ja.md`, `#{key}` from
  // messages_ja.properties, `<html lang>`, the hreflang alternates, the
  // sitemap's xhtml:link; a page without its translation is written with
  // the default text, its canonical the default page, out of the sitemap.
  test('a page per language under /<language>', () async {
    final files = _Memory({'web/index.html': _index});
    final logs = await _build(
      files,
      {
        ..._site(),
        'application.yml':
            '$_config\n'
            'spring.flutter.navigation.languages: en, ja\n',
        'messages.properties': 'nav.account=Account\n',
        'messages_ja.properties': 'nav.account=アカウント\n',
        'content/docs/core/configuration.ja.md':
            '---\ntitle: 設定\ndescription: 設定の読み方。\n---\n'
            '# 設定\n\n[ビーン](beans.md)と[索引](../index.ja.md)。\n',
      },
      metadata: jsonEncode({
        'routes': [
          ...(jsonDecode(_routes) as Map)['routes'] as List,
          {'path': '/me', 'class': 'MePage', 'title': '#{nav.account}'},
        ],
      }),
    );
    expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);

    final ja = files.files['web/ja/docs/core/configuration/index.html']!;
    expect(ja, contains('<html lang="ja">'));
    expect(ja, contains('<title>設定 · Spring Dart</title>'));
    expect(ja, contains('content="設定の読み方。"'));
    expect(
      ja,
      contains(
        '<link rel="canonical" '
        'href="https://spring-dart.dev/ja/docs/core/configuration">',
      ),
    );
    expect(ja, contains('<a href="/ja/docs/core/beans">ビーン</a>'));
    expect(ja, contains('<a href="/ja/docs">索引</a>'));
    for (final link in [
      'hreflang="en" href="https://spring-dart.dev/docs/core/configuration"',
      'hreflang="ja" href="https://spring-dart.dev/ja/docs/core/configuration"',
      'hreflang="x-default" href="https://spring-dart.dev/docs/core/configuration"',
    ]) {
      expect(ja, contains(link));
      expect(
        files.files['web/docs/core/configuration/index.html'],
        contains(link),
      );
    }
    expect(
      files.files['web/docs/core/configuration/index.html'],
      contains('<html lang="en">'),
    );
    expect(files.files['web/ja/docs/core/configuration.md'], contains('# 設定'));

    // Not translated: the default text, canonical to the default page,
    // noindex, no alternates, no .md copy.
    final beans = files.files['web/ja/docs/core/beans/index.html']!;
    expect(beans, contains('<html lang="ja">'));
    expect(beans, contains('<title>Beans · Spring Dart</title>'));
    expect(
      beans,
      contains(
        '<link rel="canonical" href="https://spring-dart.dev/docs/core/beans">',
      ),
    );
    expect(beans, contains('<meta name="robots" content="noindex">'));
    expect(beans, isNot(contains('hreflang')));
    expect(files.files, isNot(contains('web/ja/docs/core/beans.md')));

    // A route's #{key} title in each language; the root as /ja.
    expect(
      files.files['web/ja/me/index.html'],
      contains('<title>アカウント · Spring Dart</title>'),
    );
    expect(
      files.files['web/me/index.html'],
      contains('<title>Account · Spring Dart</title>'),
    );
    expect(files.files, contains('web/ja/index.html'));

    // The sitemap: the translated page in both languages, with alternates;
    // the fallback page left out.
    final sitemap = files.files['web/sitemap.xml']!;
    expect(sitemap, contains('xmlns:xhtml="http://www.w3.org/1999/xhtml"'));
    expect(
      sitemap,
      contains('<loc>https://spring-dart.dev/ja/docs/core/configuration</loc>'),
    );
    expect(
      sitemap,
      contains(
        '<xhtml:link rel="alternate" hreflang="ja" '
        'href="https://spring-dart.dev/ja/docs/core/configuration"/>',
      ),
    );
    expect(sitemap, isNot(contains('/ja/docs/core/beans<')));
    // The translation file makes no page of its own.
    expect(
      files.files,
      isNot(contains('web/docs/core/configuration.ja/index.html')),
    );
  });

  test('a language that is no tag fails the build', () async {
    final files = _Memory({'web/index.html': _index});
    final logs = await _build(files, {
      ..._site(),
      'application.yml':
          '$_config\n'
          'spring.flutter.navigation.languages: en, ../x\n',
    }, metadata: _routes);
    expect(logs, contains(allOf(startsWith('SEVERE'), contains('../x'))));
  });
}
