// The module a release build leaves out, as the generator lists it in the
// example's application: under `!dart.vm.product`, since the example does
// not set spring.main.startup-checks.enabled.
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  test('the warning list is not in a release build by default', () {
    final code = File(
      Isolate.resolvePackageUriSync(
        Uri.parse(
          'package:spring_boot_starter_edge/spring_boot_starter_edge.dart',
        ),
      )!.resolve('../example/spring_gen/main.spring.dart').toFilePath(),
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    expect(
      code,
      matches(
        RegExp(
          r"if\(!constbool\.fromEnvironment\('dart\.vm\.product'\)\)"
          r'_i\d+\.springBootStarterEdgeStartupChecksAutoConfiguration,',
        ),
      ),
    );
  });
}
