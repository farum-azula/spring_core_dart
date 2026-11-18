// spring_boot_actuator's part: an application that lists the actuator gets
// build-info.properties among its resources, from its pubspec.yaml.
import 'package:test/test.dart';

import '../support/example_application.dart';

void main() {
  const actuatorApp =
      'name: pkg\nversion: 1.2.3\npublish_to: none\n'
      'dependencies:\n  spring_boot_dart: any\n'
      '  spring_boot_starter_actuator: any\n';

  const plainApp =
      'name: pkg\nversion: 1.2.3\npublish_to: none\n'
      'dependencies:\n  spring_boot_dart: any\n';

  const publishedPackage =
      'name: pkg\nversion: 1.2.3\n'
      'dependencies:\n  spring_boot_dart: any\n'
      '  spring_boot_starter_actuator: any\n';

  test('an application with the actuator: build-info.properties of its '
      'pubspec', () async {
    final output = await generateEntryPoint(
      'lib/main.dart',
      pubspec: actuatorApp,
    );
    expect(
      output,
      contains(r'build.artifact=pkg\nbuild.name=pkg\nbuild.version=1.2.3'),
    );
  });

  test('no build-info.properties without the actuator, or for a published '
      'package', () async {
    for (final pubspec in [plainApp, publishedPackage]) {
      expect(
        await generateEntryPoint('lib/main.dart', pubspec: pubspec),
        isNot(contains('build.version')),
      );
    }
  });
}
