// Where @Scheduled goes: a public instance method of a bean; elsewhere the build fails, naming what to change.
import 'package:test/test.dart';

import '../support/placements.dart';

void main() {
  group('misplaced', () {
    misplacedCases({
      '@Scheduled in a class that is no bean': (
        'class Report { @Scheduled(fixedRate: Duration(minutes: 1)) void '
            'run() {} }',
        ['@Scheduled on Report.run, and Report is no bean'],
      ),
      '@Scheduled on a getter': (
        '@Component() class R { @Scheduled(fixedRate: Duration(minutes: 1)) '
            'int get run => 1; }',
        [
          '@Scheduled on the getter R.run: it goes on a method, where the '
              'scheduler runs it',
        ],
      ),
    });
  });

  placedCase('in their places they build', '''
@Component()
class Jobs {
  @Scheduled(fixedRate: Duration(minutes: 1))
  void tick() {}
}
''');
}
