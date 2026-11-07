// The head of web/index.html from spring.flutter.app.*: the template's
// values replaced, and a page with the SEO build's head keeping the title
// and description the SEO build wrote for it.
import 'package:spring_core_dart_generator/src/web_page_head.dart';
import 'package:test/test.dart';

const _template = '''
<head>
  <meta name="description" content="A new Flutter project.">
  <meta name="apple-mobile-web-app-title" content="app">
  <title>app</title>
</head>
''';

void main() {
  test("the app title and description replace the template's", () {
    final html = WebPageHead.html(
      _template,
      title: 'Lumen',
      description: 'A library.',
    );
    expect(html, contains('<title>Lumen</title>'));
    expect(html, contains('<meta name="description" content="A library.">'));
    expect(
      html,
      contains('<meta name="apple-mobile-web-app-title" content="Lumen">'),
    );
  });

  test('a page with the SEO head keeps its title and description', () {
    const page =
        '''
<head>
  <meta name="apple-mobile-web-app-title" content="app">
  <title>Lumen, a small library · Lumen</title>
  ${WebPageHead.seoHeadStart}
  <meta name="description" content="The home page.">
  <!-- spring:seo:head:end -->
</head>
''';
    final html = WebPageHead.html(
      page,
      title: 'Lumen',
      description: 'A library.',
      themeColor: '#123456',
    );
    expect(html, contains('<title>Lumen, a small library · Lumen</title>'));
    expect(html, contains('content="The home page."'));
    expect(html, isNot(contains('A library.')));
    // The home screen's name and the color are the app's, as before.
    expect(
      html,
      contains('<meta name="apple-mobile-web-app-title" content="Lumen">'),
    );
    expect(html, contains('<meta name="theme-color" content="#123456">'));
  });

  test("a page without a viewport gets Flutter's; its own is kept", () {
    final html = WebPageHead.html(_template);
    expect(
      html,
      contains('<meta name="viewport" content="${WebPageHead.viewport}">'),
    );
    expect(WebPageHead.html(html), html, reason: 'written once');
    const own =
        '<head>\n  <meta name="viewport" content="width=500">\n</head>\n';
    expect(WebPageHead.html(own), own);
  });

  test("the page's background is the theme's, written once", () {
    final html = WebPageHead.html(_template, backgroundColor: '#0d1017');
    expect(html, contains('html,body{background-color:#0d1017}'));
    expect(WebPageHead.html(html, backgroundColor: '#0d1017'), html);
    expect(
      WebPageHead.html(html),
      isNot(contains(WebPageHead.backgroundStart)),
    );
  });

  test('a light and a dark theme: the background and theme-color of each, '
      'written once', () {
    String write(String page) => WebPageHead.html(
      page,
      themeColor: '#8a6a00',
      backgroundColor: '#f5f6f9',
      darkThemeColor: '#d4c664',
      darkBackgroundColor: '#0d1017',
    );
    final once = write(_template);
    expect(
      once,
      contains(
        'html,body{background-color:#f5f6f9}@media '
        '(prefers-color-scheme:dark){html,body{background-color:#0d1017}}',
      ),
    );
    expect(
      once,
      contains(
        '<meta name="theme-color" content="#8a6a00" '
        'media="(prefers-color-scheme: light)">',
      ),
    );
    expect(
      once,
      contains(
        '<meta name="theme-color" content="#d4c664" '
        'media="(prefers-color-scheme: dark)">',
      ),
    );
    expect(write(once), once);
    // Back to one theme: one tag, no dark rule.
    final single = WebPageHead.html(
      once,
      themeColor: '#8a6a00',
      backgroundColor: '#f5f6f9',
    );
    expect(single, isNot(contains('prefers-color-scheme')));
    expect(single, contains('<meta name="theme-color" content="#8a6a00">'));
  });
}
