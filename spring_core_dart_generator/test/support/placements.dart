// What the parts' placement tests share: a source with the imports of the
// starters (the real packages), built with every part, expected to fail
// with each message, or to build.
import 'package:spring_core_dart_generator/src/core/beans/bean_scanner.dart';
import 'package:test/test.dart';

import 'spring_builder.dart';

/// The imports of the starters whose annotations the placement tests use.
const starterImports = '''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_cache/spring_boot_starter_cache.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_scheduling/spring_boot_starter_scheduling.dart';
import 'package:spring_boot_starter_feign/spring_boot_starter_feign.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:spring_boot_actuator/spring_boot_actuator.dart';
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
''';

/// Builds [source] (after [starterImports]) in `pkg`'s scanned directory.
Future<({bool succeeded, String errors})> buildWithStarters(
  String source,
) async {
  final result = await buildPackage({
    'lib/src/beans.dart': scanRoot,
    'lib/src/service.dart': '$starterImports$source',
  }, proxyMode: ProxyMode.all);
  return (succeeded: result.succeeded, errors: result.errors.join('\n'));
}

/// One test per case: [source] fails the build with every message.
void misplacedCases(Map<String, (String, List<String>)> cases) {
  for (final MapEntry(key: name, value: (source, messages)) in cases.entries) {
    test(name, () async {
      final result = await buildWithStarters(source);
      expect(result.succeeded, isFalse, reason: source);
      for (final message in messages) {
        expect(result.errors, contains(message));
      }
    });
  }
}

/// A test that [source] builds.
void placedCase(String name, String source) {
  test(name, () async {
    final result = await buildWithStarters(source);
    expect(result.errors, isEmpty);
  });
}
