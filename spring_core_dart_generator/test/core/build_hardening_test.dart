// What a build must not put in an app, and what it must decide alike
// everywhere: secret-looking files and defines stay out of a client build,
// generated literals read back as written, build keys ignore profiles, and
// the fingerprint follows the beans of nested modules.
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:code_builder/code_builder.dart';
import 'package:spring_core_dart_generator/src/core/builder/build_inclusion.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/core/introspection/json_schemas/json_schema_classes.dart';
import 'package:spring_core_dart_generator/src/navigation/seo_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

import '../support/module_files.dart';
import '../support/spring_builder.dart';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => springApplication.run(args);
''';

const _flutterPubspec = 'name: pkg\nflutter:\n  uses-material-design: true\n';

Future<(TestBuilderResult, List<String>)> _application(
  Map<String, String> files, {
  String pubspec = 'name: pkg\n',
  List<String> secrets = const [],
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final logs = <String>[];
  final result = await testBuilder(
    SpringBuilder(
      generations: packageGenerations,
      dartDefinesSecrets: secrets,
    ),
    {
      'pkg|pubspec.yaml': pubspec,
      'pkg|lib/main.dart': _main,
      for (final MapEntry(:key, :value) in files.entries) 'pkg|$key': value,
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) => logs.add(record.message),
  );
  expect(result.errors, isEmpty);
  return (result, logs);
}

String _environment(TestBuilderResult result) => result.readerWriter.testing
    .readString(AssetId('pkg', 'lib/spring_gen/main.spring.env.dart'));

void main() {
  group('resources that look like secrets (F1)', () {
    test('are left out with a warning; the others stay', () async {
      final (result, logs) = await _application({
        'lib/resources/.env': 'A=1',
        'lib/resources/keys/server.pem': 'PRIVATE',
        'lib/resources/banner.txt': 'BANNER',
      });
      final module = moduleText(
        result,
        AssetId('pkg', 'lib/spring_gen/main.spring.dart'),
      );
      expect(module, isNot(contains('PRIVATE')));
      expect(module, isNot(contains("r'.env'")));
      expect(module, contains("r'banner.txt'"));
      expect(logs.join('\n'), contains('look like a secret'));
    });

    test('spring.resources.embed.secrets embeds one anyway', () async {
      final (result, _) = await _application({
        'lib/resources/application.yml':
            'spring:\n  resources:\n    embed:\n      secrets: [public.pem]\n',
        'lib/resources/public.pem': 'PUBLIC',
      });
      expect(
        moduleText(result, AssetId('pkg', 'lib/spring_gen/main.spring.dart')),
        contains('PUBLIC'),
      );
    });
  });

  group('defines that look like secrets in a client build (F8)', () {
    const config = {
      'lib/resources/application.yml':
          r'shop: {url: "${SHOP_URL:x}", password: "${SHOP_PASSWORD:x}"}'
          '\n',
    };

    test('a Flutter app leaves them out and says so', () async {
      final (result, logs) = await _application(
        config,
        pubspec: _flutterPubspec,
      );
      final environment = _environment(result);
      expect(environment, contains('SHOP_URL'));
      expect(environment, isNot(contains('SHOP_PASSWORD')));
      expect(logs.join('\n'), contains('dart_defines_secrets'));
    });

    test('dart_defines_secrets keeps them', () async {
      final (result, _) = await _application(
        config,
        pubspec: _flutterPubspec,
        secrets: const ['SHOP_PASSWORD'],
      );
      expect(_environment(result), contains('SHOP_PASSWORD'));
    });

    test('a placeholder of a public property stays public', () async {
      final (result, _) = await _application(
        const {
          'lib/resources/application.yml':
              'shop:\n  public-key: \${SHOP_ANON_KEY}\n',
        },
        pubspec: _flutterPubspec,
        secrets: const ['shop.public-key'],
      );
      expect(_environment(result), contains('SHOP_ANON_KEY'));
    });

    test('a server keeps them', () async {
      final (result, _) = await _application(config);
      expect(_environment(result), contains('SHOP_PASSWORD'));
    });
  });

  test('a schema class masks a secret-looking field in toString (F2)', () {
    const schema =
        '{"title": "Login", "type": "object", "required": ["password"], '
        '"properties": {"password": {"type": "string"}}}';
    final code = JsonSchemaClasses.code([
      (
        entry: (
          location: 'resources:login.json',
          sha256: null,
          prefix: '',
          name: null,
        ),
        text: schema,
        document: const {
          'title': 'Login',
          'type': 'object',
          'required': ['password'],
          'properties': {
            'password': {'type': 'string'},
          },
        },
        resource: 'login.json',
      ),
    ], report: false)!;
    expect(code, contains('password: ******'));
    expect(code, isNot(contains(r'password: $password')));
  });

  test('a schema prefix keeps only what an identifier may hold (F6)', () {
    final entries = JsonSchemaClasses.entries({
      'application.yml':
          'spring:\n  json:\n    schemas:\n'
          '      - location: resources:a.json\n'
          "        prefix: 'A;b c'\n",
    });
    expect(entries.single.prefix, 'Abc');
  });

  test('a page path stays below web/ (F3, F4)', () {
    expect(webFilePath('web/books/one.html'), 'web/books/one.html');
    for (final path in [
      'web/../lib/pwn',
      '../../x',
      'lib/a',
      r'web\a',
      'web/%2e%2e/a',
      'web//a',
      'web/./a',
    ]) {
      expect(webFilePath(path), isNull, reason: path);
    }
  });

  test('a factory argument reads back as written (F5)', () {
    String written(String value) =>
        '${SpringBuilder.stringLiteral(value).accept(DartEmitter())}';
    expect(written(r'a$b'), r"'a\$b'");
    expect(written("it's \$x"), r"'it\'s \$x'");
  });

  group('build keys (GEN-2)', () {
    BuildInclusion decide(Map<String, String> files) => BuildKeys(
      () => files,
    ).decide('feature.on', whenMissing: BuildInclusion.never, subject: 'x');

    test('spring.profiles.active does not reach a profile file', () {
      expect(
        decide({
          'application.properties': 'spring.profiles.active=dev\n',
          'application-dev.properties': 'feature.on=true\n',
        }),
        BuildInclusion.never,
      );
    });

    test('a document limited to a profile is not read', () {
      expect(
        decide({
          'application.yml':
              'a: 1\n---\nspring:\n  config:\n    activate:\n'
              '      on-profile: "!prod"\nfeature:\n  on: true\n',
        }),
        BuildInclusion.never,
      );
    });

    test("Spring's boolean spellings", () {
      for (final value in ['yes', 'on', '1']) {
        expect(
          decide({'application.properties': 'feature.on=$value\n'}),
          BuildInclusion.always,
        );
      }
      expect(
        BuildKeys(
          () => {'application.properties': 'feature.on=off\n'},
        ).decide(
          'feature.on',
          whenMissing: BuildInclusion.always,
          subject: 'x',
        ),
        BuildInclusion.never,
      );
    });
  });

  test(
    'the fingerprint changes with a bean of a nested module (GEN-1)',
    () async {
      Future<String> fingerprint(String beans) async {
        final (result, _) = await _application({
          'lib/src/beans.dart': scanRoot,
          'lib/src/service.dart': '$coreImport$beans',
        });
        final debug = result.readerWriter.testing.readString(
          AssetId('pkg', 'lib/spring_gen/main.spring.debug.dart'),
        );
        return RegExp(r"_\$fingerprint = '(\w+)'").firstMatch(debug)![1]!;
      }

      expect(
        await fingerprint('@Component() class A {}'),
        isNot(
          await fingerprint(
            '@Component() class A {}\n@Component() class B { B(A a); }',
          ),
        ),
      );
    },
  );
}
