// tool/affected.dart: which packages a change affects, so CI runs only
// their tests. A dev dependency counts only when the package's tests use
// it; the generator only when it writes code the tests run.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../affected.dart';
import '../version.dart' as family;

void main() {
  group('rules (a temporary layout)', () {
    late Directory root;

    void write(String path, String text) => File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);

    setUp(() {
      root = Directory.systemTemp.createTempSync('affected_');
      write('core/pubspec.yaml', 'name: core\n');
      write('boot/pubspec.yaml', 'name: boot\ndependencies:\n  core: any\n');
      write('gen/pubspec.yaml', 'name: spring_core_dart_generator\n');
      write('mocks/pubspec.yaml', 'name: mocks\n');
    });

    tearDown(() => root.deleteSync(recursive: true));

    Map<String, Set<String>> dependencies(List<String> packages) =>
        localDependencies(packages, root: root.path);

    test('dependencies always count', () {
      expect(dependencies(['core', 'boot'])['boot'], {'core'});
    });

    test('a dev dependency counts when a test imports it', () {
      write(
        'app/pubspec.yaml',
        'name: app\ndev_dependencies:\n  mocks: any\n  boot: any\n',
      );
      write(
        'app/test/support/fakes.dart',
        "import 'package:mocks/mocks.dart';\n",
      );
      // Mentioned in a comment or string only: not used.
      write(
        'app/test/a_test.dart',
        '// package:boot/boot.dart\nvoid main() {}\n',
      );
      expect(dependencies(['boot', 'mocks', 'app'])['app'], {'mocks'});
    });

    test('integration_test counts like test', () {
      write('app/pubspec.yaml', 'name: app\ndev_dependencies:\n  mocks: any\n');
      write(
        'app/integration_test/app_test.dart',
        "export 'package:mocks/mocks.dart';\n",
      );
      expect(dependencies(['mocks', 'app'])['app'], {'mocks'});
    });

    test('the generator counts unless it only writes the example', () {
      const devGenerator =
          'dev_dependencies:\n  spring_core_dart_generator: any\n';
      write('app/pubspec.yaml', 'name: app\n$devGenerator');
      write('lib_pkg/pubspec.yaml', 'name: lib_pkg\n$devGenerator');
      write('lib_pkg/build.yaml', r'''
targets:
  $default:
    builders:
      spring_core_dart_generator:spring_core_dart:
        generate_for: [example/**]
      spring_core_dart_generator:spring_test:
        enabled: false
''');
      // Only the example, but test classes still generated: counts.
      write('half/pubspec.yaml', 'name: half\n$devGenerator');
      write('half/build.yaml', r'''
targets:
  $default:
    builders:
      spring_core_dart_generator:spring_core_dart:
        generate_for: [example/**]
''');
      final result = dependencies(['gen', 'app', 'lib_pkg', 'half']);
      expect(result['app'], {'gen'});
      expect(result['lib_pkg'], isEmpty);
      expect(result['half'], {'gen'});
    });

    test('dependents are affected through the chain', () {
      final packages = ['core', 'boot'];
      expect(
        affectedPackages(['core/lib/x.dart'], packages, dependencies(packages)),
        {'core', 'boot'},
      );
      expect(
        affectedPackages(['boot/lib/x.dart'], packages, dependencies(packages)),
        {'boot'},
      );
    });
  });

  group('this repository', () {
    final repo = p.dirname(p.dirname(p.fromUri(Platform.script)));
    final root = File(p.join(repo, 'pubspec.yaml')).existsSync()
        ? repo
        : Directory.current.path;
    final packages = [
      ...family.family,
      'example/server_guide',
      'extensions/language_server',
    ];
    late Map<String, Set<String>> dependencies;

    setUpAll(() => dependencies = localDependencies(packages, root: root));

    Set<String> affected(String path) =>
        affectedPackages([path], packages, dependencies);

    test('spring_core_dart depends on nothing of the family', () {
      // Its dev dependencies (spring_boot_dart, the generator) are only for
      // its example.
      expect(dependencies['spring_core_dart'], isEmpty);
    });

    test('a change in spring_boot_dart does not reach the core', () {
      expect(
        affected('spring_boot_dart/lib/x.dart'),
        isNot(contains('spring_core_dart')),
      );
      expect(
        affected('spring_boot_dart/lib/x.dart'),
        isNot(contains('spring_web_dart')),
      );
    });

    test('a generator change reaches the apps whose tests run its code', () {
      expect(affected('spring_core_dart_generator/lib/x.dart'), {
        'spring_core_dart_generator',
        // Their tests start what the generator writes: server endpoints
        // (test/server/), controllers and secured beans (test/app/).
        'spring_security_core',
        'spring_boot_starter_websocket',
        'spring_boot_starter_web',
        'spring_boot_starter_security',
        'example/server_guide',
        // Through spring_security_core: the OAuth2 client depends on it,
        // the Flutter security package on both (the Flutter starter on
        // neither).
        'spring_boot_starter_oauth2_client',
        'spring_boot_starter_flutter_security',
      });
    });

    test('the Flutter starter reaches the Flutter security package', () {
      expect(affected('spring_boot_starter_flutter/lib/x.dart'), {
        'spring_boot_starter_flutter',
        'spring_boot_starter_flutter_security',
      });
      expect(affected('spring_boot_starter_oauth2_client/lib/x.dart'), {
        'spring_boot_starter_oauth2_client',
        'spring_boot_starter_security',
        'spring_boot_starter_flutter_security',
        'example/server_guide',
      });
    });

    test('a core change reaches everything', () {
      expect(affected('spring_core_dart/lib/x.dart'), packages.toSet());
    });

    test("the starters' applications are checked when the family changes", () {
      expect(
        familyAffected(affected('spring_boot_starter_cache/lib/x.dart')),
        isTrue,
      );
      expect(
        familyAffected(affected('spring_core_dart_generator/lib/x.dart')),
        isTrue,
      );
      expect(
        familyAffected(affected('example/server_guide/bin/x.dart')),
        isFalse,
      );
      expect(
        familyAffected(affected('spring_boot_starter_flutter/lib/x.dart')),
        isFalse,
      );
      expect(
        familyAffected(
          affected('spring_boot_starter_flutter_security/lib/x.dart'),
        ),
        isFalse,
      );
      expect(familyAffected(affected('README.md')), isFalse);
    });
  });
}
