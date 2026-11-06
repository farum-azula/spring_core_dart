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
}
