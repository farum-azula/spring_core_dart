// Where the actuator's operations go: in an @Endpoint, their selectors on an
// operation's parameters; elsewhere the build fails, naming what to change.
import 'package:test/test.dart';

import '../support/placements.dart';

void main() {
  group('misplaced', () {
    misplacedCases({
      '@ReadOperation in a component': (
        '@Component() class C { @ReadOperation() String r() => ""; }',
        ['@ReadOperation on C.r: C is no @Endpoint'],
      ),
      '@Selector off an operation': (
        '@Component() class C { void r(@Selector() String name) {} }',
        ['@Selector on parameter name of C.r: only an endpoint operation'],
      ),
    });
  });

  placedCase('in their places they build', '''
@Endpoint('stock')
class StockEndpoint {
  @ReadOperation()
  String read() => '';
}
''');

  group('@Endpoint', () {
    misplacedCases({
      'without an operation': (
        "@Endpoint(id: 'none') class E { String r() => ''; }",
        ['@Endpoint on class E: it has no operation'],
      ),
    });
  });

  placedCase('an endpoint whose operation is inherited', '''
abstract class Base { @ReadOperation() String r() => ''; }
@Endpoint(id: 'inherited') class E extends Base {}
''');
}
