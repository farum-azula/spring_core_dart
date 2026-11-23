// Where the annotations of a @FeignClient go: a method mapped by a web mapping,
// parameters that say how they are sent; elsewhere the build fails, naming what
// to change.
import 'package:test/test.dart';

import '../support/placements.dart';

void main() {
  const cannotSend =
      'Api.p: parameter me has @AuthenticationPrincipal, which a client '
      'cannot send';
  group('misplaced', () {
    misplacedCases({
      'a parameter annotation a client cannot send (S19)': (
        "@FeignClient('svc', url: 'http://x') abstract interface class Api { "
            "@PostMapping('/p') Future<String> p(@AuthenticationPrincipal() "
            'String me); }',
        [
          cannotSend,
        ],
      ),
      "another starter's mapping": (
        "@FeignClient('svc', url: 'http://x') abstract interface class Api { "
            "@EdgeFunction('hello') Future<String> h(); }",
        ['@EdgeFunction on Api.h: a @FeignClient method is mapped by'],
      ),
      '@Lazy on a client': (
        "@Lazy() @FeignClient('svc', url: 'http://x') abstract interface "
            "class Api { @GetMapping('/x') Future<String> x(); }",
        ['@Lazy on Api: its bean is made by the starter'],
      ),
    });
  });

  placedCase('in their places they build', '''
@FeignClient('svc', url: 'http://x')
abstract interface class Api {
  @GetMapping('/x/{id}')
  Future<String> x(@PathVariable() String id, @RequestParam() String q);
}
''');

  group('the client itself', () {
    misplacedCases({
      '@FeignClient on a mixin': (
        "@FeignClient('svc', url: 'http://x') mixin M {}",
        ['@FeignClient on mixin M: it belongs on a class'],
      ),
    });
  });
}
