// Where the Supabase operations go: in the interface of their kind
// (@StorageBucket, @RealtimeChannel, @EdgeFunctions); elsewhere the build
// fails, naming what to change. An @EdgeFunctions interface goes into the
// group EdgeFunctions.group, the one the starter points at the project.
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
      '@EdgeFunctions imported into another group': (
        "$_functions@Configuration() @ImportHttpServices(group: 'other', "
            'types: [Functions]) class Imports {}',
        [
          'Functions has @EdgeFunctions and is imported into the group "other"',
          'through the group "supabase-functions"',
          '@ImportHttpServices(group: EdgeFunctions.group, types: [Functions])',
        ],
      ),
      '@EdgeFunctions imported into the default group': (
        '$_functions@Configuration() @ImportHttpServices(types: [Functions]) '
            'class Imports {}',
        ['Functions has @EdgeFunctions and is imported into the group'],
      ),
    });
  });

  group('placed', () {
    placedCase(
      '@EdgeFunctions imported into EdgeFunctions.group',
      '$_functions@Configuration() @ImportHttpServices(group: '
          'EdgeFunctions.group, types: [Functions]) class Imports {}',
    );
  });
}

const _functions = '''
@EdgeFunctions()
abstract interface class Functions {
  @EdgeFunction('hello')
  Future<String> hello(@RequestBody() String name);
}
''';
