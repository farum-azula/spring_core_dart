// The modules a release build leaves out, as the generator lists them in
// the example's application: under `!dart.vm.product` when their key is not
// set, in every build when it is `true`.
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

// The example's generated application without blanks.
String _generated() => File(
  Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_boot_starter_data/spring_boot_starter_data.dart'),
  )!.resolve('../example/spring_gen/example.spring.dart').toFilePath(),
).readAsStringSync().replaceAll(RegExp(r'\s+'), '');

void main() {
  final code = _generated();

  test('the startup checks: spring.main.startup-checks.enabled not set, so '
      'not in a release build', () {
    expect(
      code,
      matches(
        RegExp(
          r"if\(!constbool\.fromEnvironment\('dart\.vm\.product'\)\)"
          r'_i\d+\.springBootStarterDataStartupChecksAutoConfiguration,',
        ),
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
