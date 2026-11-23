// Where the Supabase operations go: in the interface of their kind (@StorageBucket, @RealtimeChannel, @EdgeFunctions); elsewhere the build fails, naming what to change.
import 'package:test/test.dart';

import '../support/placements.dart';

void main() {
  group('misplaced', () {
    misplacedCases({
      '@Upload in a component': (
        "@Component() class C { @Upload('{path}') Future<void> u(String path, "
            'List<int> bytes) async {} }',
        ['@Upload on C.u: C is no @StorageBucket interface'],
      ),
      '@EdgeFunction in a component': (
        "@Component() class C { @EdgeFunction('hello') Future<String> h() "
            "async => ''; }",
        ['@EdgeFunction on C.h: C is no @EdgeFunctions interface'],
      ),
    });
  });
}
