// spring.flutter.web.page.swipe-to-close: false writes the block that
// keeps the page open on a swipe down, naming no app and calling no app's API;
// true (the default) removes it; writing it twice gives one block.
import 'package:spring_core_dart_generator/src/web_page_head.dart';
import 'package:test/test.dart';

const _page =
    '<html>\n<head>\n  <title>x</title>\n</head>\n<body></body>\n</html>\n';

void main() {
  test('written once in the head, removed again', () {
    final once = WebPageHead.swipe(_page, swipeToClose: false);
    expect(once, contains(WebPageHead.swipeStart));
    // Nothing of one app: no name, no API of a messenger.
    expect(once.toLowerCase(), isNot(contains('telegram')));
    expect(once, contains("addEventListener('touchmove'"));
    expect(once, contains('height:1000vh!important'));
    expect(
      once.indexOf(WebPageHead.swipeEnd),
      lessThan(once.indexOf('</head>')),
    );
    final twice = WebPageHead.swipe(once, swipeToClose: false);
    expect(WebPageHead.swipeStart.allMatches(twice), hasLength(1));
    expect(WebPageHead.swipe(twice, swipeToClose: true), _page);
    expect(WebPageHead.swipe(_page, swipeToClose: true), _page);
  });
}
