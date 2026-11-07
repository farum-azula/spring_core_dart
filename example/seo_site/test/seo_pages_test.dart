// What the build wrote into web/ for search engines, link previews and
// language models (spring.flutter.web.seo.* in application-web.yml): a page
// per address with its own head and hidden text, the sitemap without the
// noindex page, robots.txt, llms.txt and the Markdown copies.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _page(String path) => File(
  path == '/' ? 'web/index.html' : 'web$path/index.html',
).readAsStringSync();

String? _meta(String html, String name) => RegExp(
  '<meta (?:name|property)="$name" content="([^"]*)"',
).firstMatch(html)?[1];

String? _title(String html) =>
    RegExp('<title>([^<]*)</title>').firstMatch(html)?[1];

void main() {
  test('every page has its own title, description and canonical address', () {
    const pages = {
      '/': (
        'Lumen, a small library · Lumen',
        'Lumen, a small library, and its documentation.',
      ),
      '/docs': (
        'Documentation · Lumen',
        'Everything about Lumen, from the first install to the routes.',
      ),
      '/docs/getting-started': (
        'Getting started · Lumen',
        'Install Lumen and show the first page in five minutes.',
      ),
      '/blog/hello': (
        'Hello, Lumen · Lumen',
        'Why Lumen exists, in three paragraphs.',
      ),
      '/legal/privacy': (
        'Privacy · Lumen',
        'What the site keeps about its visitors, which is nothing.',
      ),
      '/books/1': ('Book · Lumen', 'A book about Lumen.'),
      '/about': ('About · Lumen', 'Who writes Lumen, and how to reach them.'),
    };
    pages.forEach((path, expected) {
      final html = _page(path);
      expect(_title(html), expected.$1, reason: path);
      expect(_meta(html, 'description'), expected.$2, reason: path);
      expect(
        RegExp('<link rel="canonical" href="([^"]*)"').firstMatch(html)?[1],
        // A page is a folder (page-files: directory): its address ends with
        // the slash the host redirects to.
        path == '/' ? 'https://lumen.example/' : 'https://lumen.example$path/',
        reason: path,
      );
    });
  });

  test('a page without front matter takes its first heading', () {
    expect(_title(_page('/docs/guides/routing')), 'Routing · Lumen');
  });

  test("the Markdown's text is in the page, hidden under the app", () {
    final html = _page('/docs/getting-started');
    expect(html, contains('<main id="spring-content"'));
    expect(html, contains('Add the package'));
    // A link to another Markdown file is the site's address.
    expect(html, contains('href="/docs/guides/routing#paths"'));
  });

  test('preview pictures: the page\'s own, else the site\'s', () {
    expect(
      _meta(_page('/blog/hello'), 'og:image'),
      'https://lumen.example/assets/lib/resources/images/book.png',
    );
    expect(
      _meta(_page('/docs'), 'og:image'),
      'https://lumen.example/assets/lib/resources/images/preview.png',
    );
  });

  test('the noindex page: in web/, not in the sitemap', () {
    expect(_meta(_page('/account'), 'robots'), 'noindex');
    final sitemap = File('web/sitemap.xml').readAsStringSync();
    expect(sitemap, isNot(contains('/account')));
    for (final path in [
      '/about',
      '/books/2',
      '/docs/guides/routing',
      '/legal/terms',
    ]) {
      expect(sitemap, contains('<loc>https://lumen.example$path/</loc>'));
    }
  });

  test('robots.txt, llms.txt and the Markdown copies', () {
    expect(
      File('web/robots.txt').readAsStringSync(),
      contains('Sitemap: https://lumen.example/sitemap.xml'),
    );
    final llms = File('web/llms.txt').readAsStringSync();
    expect(llms, startsWith('# Lumen, a small library'));
    expect(llms, contains('https://lumen.example/docs/getting-started.md'));
    expect(
      File('web/llms-full.txt').readAsStringSync(),
      contains('Add the package'),
    );
    expect(File('web/docs/guides/routing.md').existsSync(), isTrue);
  });

  test('excluded files make no page', () {
    expect(Directory('web/legal/_draft').existsSync(), isFalse);
    expect(
      File('web/sitemap.xml').readAsStringSync(),
      isNot(contains('_draft')),
    );
  });

  test('/ja: the pages in Japanese, with hreflang and the sitemap', () {
    final ja = _page('/ja/docs/getting-started');
    expect(ja, contains('<html lang="ja">'));
    expect(_title(ja), 'はじめに · Lumen');
    expect(
      ja,
      contains(
        '<link rel="canonical" href="https://lumen.example/ja/docs/getting-started/">',
      ),
    );
    for (final link in [
      'hreflang="en" href="https://lumen.example/docs/getting-started/"',
      'hreflang="ja" href="https://lumen.example/ja/docs/getting-started/"',
      'hreflang="x-default" href="https://lumen.example/docs/getting-started/"',
    ]) {
      expect(ja, contains(link));
      expect(_page('/docs/getting-started'), contains(link));
    }
    expect(_page('/docs/getting-started'), contains('<html lang="en">'));
    expect(_title(_page('/ja/about')), '概要 · Lumen');
    expect(
      File('web/ja/docs/getting-started.md').readAsStringSync(),
      contains('# はじめに'),
    );

    // Not translated: the English text, the English page canonical,
    // noindex, out of the sitemap.
    final routing = _page('/ja/docs/guides/routing');
    expect(_title(routing), 'Routing · Lumen');
    expect(
      routing,
      contains(
        '<link rel="canonical" href="https://lumen.example/docs/guides/routing/">',
      ),
    );
    expect(routing, contains('<meta name="robots" content="noindex">'));

    final sitemap = File('web/sitemap.xml').readAsStringSync();
    expect(sitemap, contains('<loc>https://lumen.example/ja/docs/</loc>'));
    expect(
      sitemap,
      contains(
        '<xhtml:link rel="alternate" hreflang="ja" href="https://lumen.example/ja/docs/"/>',
      ),
    );
    expect(sitemap, isNot(contains('/ja/docs/guides/routing<')));
    // A translation file is no page of its own.
    expect(Directory('web/docs/getting-started.ja').existsSync(), isFalse);
  });
}
