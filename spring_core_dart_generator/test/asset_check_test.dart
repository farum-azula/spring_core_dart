// `@Value('asset:...')` (spring_boot_starter_flutter's assets): the build
// fails when the asset is missing or not declared under `flutter: assets:`
// in pubspec.yaml, with the line to add, instead of the app failing when it
// reads the asset.
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

const _assets = r'''
import 'package:spring_core_dart/spring_core_dart.dart';

@Component()
class AppAssets {
  AppAssets(@Value('asset:assets/images/logo.png') this.logo);
  final Resource logo;
}
''';

const _pubspec = '''
name: pkg
flutter:
  assets:
    - assets/images/
''';

Future<TestBuilderResult> _build(
  Map<String, String> files, {
  String app = _assets,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return testBuilder(
    SpringBuilder(),
    {
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/app.dart': app,
      for (final MapEntry(:key, :value) in files.entries) 'pkg|$key': value,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
}

Future<String> _errors(
  Map<String, String> files, {
  String app = _assets,
}) async {
  final result = await _build(files, app: app);
  expect(result.succeeded, isFalse);
  return result.errors.join('\n');
}

void main() {
  test('a declared asset that exists builds', () async {
    final result = await _build({
      'pubspec.yaml': _pubspec,
      'assets/images/logo.png': 'png',
    });
    expect(result.errors, isEmpty);
  });

  test('a file entry and a path: entry declare it too', () async {
    for (final pubspec in [
      'name: pkg\nflutter:\n  assets:\n    - assets/images/logo.png\n',
      'name: pkg\nflutter:\n  assets:\n    - path: assets/images/\n'
          '      flavors: [prod]\n',
    ]) {
      final result = await _build({
        'pubspec.yaml': pubspec,
        'assets/images/logo.png': 'png',
      });
      expect(result.errors, isEmpty, reason: pubspec);
    }
  });

  test('an undeclared asset fails with the pubspec lines to add', () async {
    final errors = await _errors({
      'pubspec.yaml': 'name: pkg\nflutter:\n  assets:\n    - assets/texts/\n',
      'assets/images/logo.png': 'png',
    });
    expect(
      errors,
      allOf(
        contains("@Value('asset:assets/images/logo.png') in "),
        contains('assets/images/logo.png is not declared in pubspec.yaml'),
        contains('flutter:\n  assets:\n    - assets/images/'),
      ),
    );
  });

  test('a directory entry does not declare its subdirectories', () async {
    final errors = await _errors({
      'pubspec.yaml': 'name: pkg\nflutter:\n  assets:\n    - assets/\n',
      'assets/images/logo.png': 'png',
    });
    expect(errors, contains('    - assets/images/'));
  });

  test('a missing file fails', () async {
    final errors = await _errors({'pubspec.yaml': _pubspec});
    expect(
      errors,
      contains('there is no file assets/images/logo.png in the package pkg'),
    );
  });

  test('every problem in one build', () async {
    final errors = await _errors(
      {'pubspec.yaml': 'name: pkg\n', 'assets/a.txt': 'a'},
      app: r'''
import 'package:spring_core_dart/spring_core_dart.dart';

@Component()
class Texts {
  Texts(
    @Value('asset:/assets/a.txt') this.a,
    @Value('asset:assets/b.txt') this.b,
  );
  final Resource a;
  final Resource b;
}
''',
    );
    expect(errors, contains('assets/a.txt is not declared'));
    expect(errors, contains('there is no file assets/b.txt'));
  });

  test('placeholders, SpEL and other packages are not checked', () async {
    final result = await _build(
      {'pubspec.yaml': 'name: pkg\n'},
      app: r'''
import 'package:spring_core_dart/spring_core_dart.dart';

@Component()
class Sounds {
  Sounds(
    @Value(r'asset:${sound.file:assets/tap.mp3}') this.tap,
    @Value('asset:packages/icons/assets/star.png') this.star,
  );
  final Resource tap;
  final Resource star;
}
''',
    );
    expect(result.errors, isEmpty);
  });
}
