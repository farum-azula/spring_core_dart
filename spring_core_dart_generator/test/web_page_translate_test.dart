// spring.flutter.web.page.translate: false keeps browsers and Google from
// offering a translation of a page whose text Flutter draws on a canvas.
import 'package:spring_core_dart_generator/src/web_page_head.dart';
import 'package:test/test.dart';

const _page = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <title>app</title>
</head>
<body></body>
</html>
''';

void main() {
  test('false: translate="no" and the notranslate meta, once', () {
    final once = WebPageHead.translate(_page, translate: false);
    expect(once, contains('<html lang="en" translate="no">'));
    expect(once, contains('<meta name="google" content="notranslate">'));
    final twice = WebPageHead.translate(once, translate: false);
    expect(twice, once);
  });

  test('true: what the build wrote is removed, the page as it was', () {
    final off = WebPageHead.translate(_page, translate: false);
    expect(WebPageHead.translate(off, translate: true), _page);
    expect(WebPageHead.translate(_page, translate: true), _page);
  });

  test("true: the page's own translate attribute stays", () {
    final own = _page.replaceFirst(
      '<html lang="en">',
      '<html lang="en" translate="no">',
    );
    expect(WebPageHead.translate(own, translate: true), own);
    expect(
      WebPageHead.translate(own, translate: false),
      contains('<html lang="en" translate="no">'),
    );
  });
}
