// `@SpringBootApplication` under example/ (a package's example on pub.dev):
// only example/ is scanned and the package's own auto-configuration is
// used, as for any application depending on the package. Elsewhere (bin/,
// lib/) the package's lib/ is scanned and its own auto-configuration is
// not, as before.
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:test/test.dart';

import '../support/example_application.dart';

void main() {
  test('example/: own auto-configuration, lib/ not scanned', () async {
    final output = await generateEntryPoint('example/main.dart');
    expect(output, contains('pkgAutoConfiguration'));
    expect(output, contains('ExampleGreeter'));
    expect(output, isNot(contains('StarterService')));
  });

  test(
    "example/: example/lib/resources/ embedded, winning over lib/'s",
    () async {
      final output = await generateEntryPoint('example/main.dart');
      expect(output, contains('a=example'));
      expect(output, isNot(contains('a=lib')));
      expect(output, contains('EXAMPLE BANNER'));
    },
  );

  test(
    'a deeper example: the nearest lib/resources/ wins, the others too',
    () async {
      final output = await generateEntryPoint('example/shop/main.dart');
      expect(output, contains('a=shop'));
      expect(output, isNot(contains('a=example')));
      expect(output, contains('EXAMPLE BANNER'));
    },
  );

  test('the resource directories of an entry point, lowest first', () {
    expect(SpringBuilder.resourceDirectories(null), ['lib/resources/']);
    expect(SpringBuilder.resourceDirectories('lib/src'), ['lib/resources/']);
    expect(SpringBuilder.resourceDirectories('example'), [
      'lib/resources/',
      'example/lib/resources/',
    ]);
    expect(SpringBuilder.resourceDirectories('example/shop/bin'), [
      'lib/resources/',
      'example/lib/resources/',
      'example/shop/lib/resources/',
      'example/shop/bin/lib/resources/',
    ]);
  });

  test("a pub workspace: only the dependencies' auto-configurations", () async {
    // The package config lists every package of this repository (a
    // workspace), the web starter among them; the app depends on
    // spring_boot_dart only.
    final output = await generateEntryPoint(
      'bin/main.dart',
      pubspec: 'name: pkg\ndependencies:\n  spring_boot_dart: any\n',
    );
    expect(output, contains('springBootAutoConfiguration'));
    expect(output, isNot(contains('springBootStarterWebAutoConfiguration')));
    expect(
      output,
      isNot(contains('springBootStarterRestclientAutoConfiguration')),
    );
  });

  test('bin/: only lib/resources/ embedded', () async {
    final output = await generateEntryPoint('bin/main.dart');
    expect(output, contains('a=lib'));
    expect(output, isNot(contains('EXAMPLE BANNER')));
  });

  test('bin/: lib/ scanned, own auto-configuration not used', () async {
    final output = await generateEntryPoint('bin/main.dart');
    expect(output, isNot(contains('pkgAutoConfiguration')));
    expect(output, contains('ExampleGreeter'));
    expect(output, contains('StarterService'));
  });

  // pub.dev refuses a package whose lib/ imports a package that is not in
  // its `dependencies`: a starter has spring_boot_dart (which re-exports
  // the container) and not spring_core_dart.
  test('without spring_core_dart in the dependencies, the container API '
      'comes through spring_boot_dart', () async {
    final output = await generateEntryPoint(
      'bin/main.dart',
      pubspec: 'name: pkg\ndependencies:\n  spring_boot_dart: any\n',
    );
    expect(
      output,
      contains("import 'package:spring_boot_dart/spring_boot_dart.dart'"),
    );
    expect(output, isNot(contains('package:spring_core_dart/')));
  });

  test(
    'with spring_core_dart in the dependencies, it is imported directly',
    () async {
      final output = await generateEntryPoint(
        'bin/main.dart',
        pubspec:
            'name: pkg\ndependencies:\n  spring_boot_dart: any\n'
            '  spring_core_dart: any\n',
      );
      expect(
        output,
        contains("import 'package:spring_core_dart/spring_core_dart.dart'"),
      );
    },
  );
}
