// The module a release build leaves out, as the generator lists it in the
// example's application: in its debug part (`_$debugAutoConfigurations`),
// which the library spreads in under `!dart.vm.product`, since the example
// does not set spring.main.startup-checks.enabled.
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

void main() {
  test('the warning list is not in a release build by default', () {
    String generated(String file) => File(
      Isolate.resolvePackageUriSync(
        Uri.parse(
          'package:spring_boot_starter_edge/spring_boot_starter_edge.dart',
        ),
      )!.resolve('../example/spring_gen/$file').toFilePath(),
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    expect(
      generated('main.spring.debug.dart'),
      matches(
        RegExp(
          r'_\$debugAutoConfigurations=>\[[^\]]*'
          r'_i\d+\.springBootStarterEdgeStartupChecksAutoConfiguration,',
        ),
      ),
    );
    expect(
      generated('main.spring.dart'),
      contains(
        "if(!constbool.fromEnvironment('dart.vm.product'))"
        r'..._$debugAutoConfigurations',
      ),
    );
  });
}
