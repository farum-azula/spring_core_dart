// The modules a profile or a release build leaves out, as the generator
// lists them in the example's application: in its debug part
// (`_$debugAutoConfigurations`, spread in under `!dart.vm.product` and
// `!dart.vm.profile`) when their key is not set, in every build when it is
// `true`.
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

// A file of the example's generated application without blanks.
String _generated([String file = 'example.spring.dart']) => File(
  Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_boot_starter_data/spring_boot_starter_data.dart'),
  )!.resolve('../example/spring_gen/$file').toFilePath(),
).readAsStringSync().replaceAll(RegExp(r'\s+'), '');

void main() {
  final code = _generated();

  test('the startup checks: spring.main.startup-checks.enabled not set, so '
      'in debug builds only', () {
    expect(
      _generated('example.spring.debug.dart'),
      matches(
        RegExp(
          r'_\$debugAutoConfigurations=>\[[^\]]*'
          r'_i\d+\.springBootStarterDataStartupChecksAutoConfiguration,',
        ),
      ),
    );
    expect(
      code,
      contains(
        "if(!constbool.fromEnvironment('dart.vm.product')&&"
        "!constbool.fromEnvironment('dart.vm.profile'))"
        r'..._$debugAutoConfigurations',
      ),
    );
  });

  test('the statement logging: show-sql=true in application.properties, so '
      'in every build, before the main module', () {
    expect(
      code,
      matches(
        RegExp(
          r'_i\d+\.springBootStarterDataAutoConfiguration,'
          r'_i\d+\.springBootStarterDataSqlLoggingAutoConfiguration,',
        ),
      ),
    );
    expect(
      code,
      matches(
        RegExp(
          r'_i\d+\.springBootStarterDataSqlLoggingAutoConfiguration:'
          r"const_i\d+\.AutoConfigurationModule\(before:\[r'"
          r"springBootStarterDataAutoConfiguration'\],?\)",
        ),
      ),
    );
  });
}
