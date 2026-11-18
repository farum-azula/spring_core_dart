// spring.flutter.web.page.max-pixel-ratio writes the block that caps the
// pixel ratio Flutter draws at, before the engine starts; none removes it;
// writing it twice gives one block.
import 'package:spring_core_dart_generator/src/web_page_head.dart';
import 'package:test/test.dart';

const _page =
    '<html>\n<head>\n  <title>x</title>\n</head>\n<body></body>\n</html>\n';

void main() {
  test('written once in the head, removed again', () {
    final once = WebPageHead.pixelRatio(_page, max: 2);
    expect(once, contains('var m=2;'));
    expect(
      once.indexOf(WebPageHead.pixelRatioEnd),
      lessThan(once.indexOf('</head>')),
    );
    expect(WebPageHead.pixelRatio(_page, max: 1.5), contains('var m=1.5;'));
    final twice = WebPageHead.pixelRatio(once, max: 2);
    expect(WebPageHead.pixelRatioStart.allMatches(twice), hasLength(1));
    expect(WebPageHead.pixelRatio(twice, max: null), _page);
    expect(WebPageHead.pixelRatio(_page, max: null), _page);
  });
}
