// The module a release build leaves out, as the generator lists it in the
// example's application: under `!dart.vm.product`, since the example does
// not set spring.main.startup-checks.enabled.
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  test('the startup check is not in a release build by default', () {
    final code = File(
      Isolate.resolvePackageUriSync(
        Uri.parse(
          'package:spring_boot_starter_cache/spring_boot_starter_cache.dart',
        ),
      )!.resolve('../example/spring_gen/example.spring.dart').toFilePath(),
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    expect(
      code,
      matches(
        RegExp(
          r'_i\d+\.springBootStarterCacheAutoConfiguration,'
          r"if\(!constbool\.fromEnvironment\('dart\.vm\.product'\)\)"
          r'_i\d+\.springBootStarterCacheStartupChecksAutoConfiguration,',
        ),
      ),
    );
  });
}
