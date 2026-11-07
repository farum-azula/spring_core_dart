// spring.flutter.web.page.swipe-to-close: false writes the block that
// keeps the page open on a swipe down, with no script of Telegram's;
// true (the default) removes it; writing it twice gives one block.
import 'package:spring_core_dart_generator/src/web_page_head.dart';
import 'package:test/test.dart';

const _page =
    '<html>\n<head>\n  <title>x</title>\n</head>\n<body></body>\n</html>\n';

void main() {
  test('written once in the head, removed again', () {
    final once = WebPageHead.swipe(_page, swipeToClose: false);
    expect(once, contains(WebPageHead.swipeStart));
    expect(once, isNot(contains('Telegram')));
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
