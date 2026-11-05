// `--dart-define` values as properties: the generator lists every key the
// application can read as a `const String.fromEnvironment`, so the defines
// reach the environment on the VM, in AOT builds and on the web.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/builder.dart';
import 'package:spring_core_dart_generator/src/dart_define_keys.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _main = r'''
import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:pkg/app.dart';

import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) {
  final context = runApplication([
    '--spring.main.banner-mode=off',
    '--logging.level.root=off',
    // The workspace's auto-configurations are all found: no web server.
    '--spring.main.web-application-type=none',
  ]);
  final api = context.getBean<Api>();
  print('RESULT ${jsonEncode({
    'url': api.url,
    'timeout': context.getBean<ApiProperties>().timeout,
    'profiles': context.environment.activeProfiles,
    'beta': context.containsBean('betaFeature'),
  })}');
  context.close();
}
''';

const _app = r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@Service()
class Api {
  Api(@Value(r'${API_URL:${api.fallback-url:none}}') this.url);
  final String url;
}

@ConfigurationProperties('api')
class ApiProperties {
  int timeout = 1;
  ApiRetry retry = ApiRetry();
}

class ApiRetry {
  int maxAttempts = 3;
}

@Component()
@ConditionalOnProperty('enabled', prefix: 'feature.beta')
class BetaFeature {}
''';

const _properties = r'''
# comment
api.fallback-url=https://fallback
shop.greeting = Hello ${shop.owner:nobody}
spring.application.name: app
''';

Future<(Map<String, String>, String)> _build() async {
  final sources = {
    'lib/app.dart': _app,
    'bin/main.dart': _main,
    'lib/resources/application.properties': _properties,
    'lib/resources/application-prod.yml':
        'cache:\n  ttl: 5m\n'
        'hosts:\n  - a\n  - \${HOST_B:b}\n',
    'lib/resources/other.properties': 'not.read=1',
  };
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  final output = readerWriter.testing.readString(
    result.outputs.singleWhere(
      (o) => o.path == 'bin/spring_gen/main.spring.dart',
    ),
  );
  return (sources, output);
}

void main() {
  group('DartDefineKeys', () {
    test('placeholders: defaults, nesting, keys built from placeholders', () {
      final keys = DartDefineKeys()
        ..addPlaceholders(r'${a} and ${b.c:${d-e:x}} ${${f}.g} #{x} ${ }');
      expect(
        keys.keys,
        containsAll(['a', 'A', 'b.c', 'B_C', 'd-e', 'DE', 'f', 'F']),
      );
      expect(keys.keys, isNot(contains('f}.g')));
    });

    test('environment form like Spring Boot', () {
      expect(
        DartDefineKeys.environmentForm('shop.max-basket-size'),
        'SHOP_MAXBASKETSIZE',
      );
      expect(
        DartDefineKeys.environmentForm('app.servers[0].host'),
        'APP_SERVERS_0_HOST',
      );
      expect(DartDefineKeys.environmentForm('list[1]'), 'LIST_1');
      expect(DartDefineKeys.environmentForm('API_URL'), 'API_URL');
    });

    test('config files: only application*, properties and YAML', () {
      final keys = DartDefineKeys()
        ..addConfigFile('application.properties', _properties)
        ..addConfigFile('config/application-dev.yaml', 'a:\n  b: \${c}\n')
        ..addConfigFile('other.properties', 'not.read=1');
      expect(
        keys.keys,
        containsAll([
          'api.fallback-url',
          'shop.greeting',
          'shop.owner',
          'spring.application.name',
          'a.b',
          'c',
        ]),
      );
      expect(keys.keys, isNot(contains('not.read')));
      expect(keys.keys, isNot(contains('#')));
    });

    test('without: the names under a prefix, in both forms', () {
      expect(
        DartDefineKeys.without(
          [
            'DEBUG',
            'SPRING_FLUTTER_THEME',
            'SPRING_FLUTTER_THEME_MODE',
            'SPRING_FLUTTER_THEMES',
            'spring.flutter.theme',
            'spring.flutter.theme.mode',
            'spring.flutter.theme[0]',
            'spring.flutter.themes',
          ],
          ['spring.flutter.theme'],
        ),
        ['DEBUG', 'SPRING_FLUTTER_THEMES', 'spring.flutter.themes'],
      );
      expect(DartDefineKeys.without(['a', 'B'], const []), ['a', 'B']);
    });

    group('without: relaxed, whole-segment prefixes', () {
      const keys = [
        'APP_A_B',
        'APP_SECRETKEY',
        'APP_SERVERS_0_HOST',
        'DEBUG',
        'SPRING_DATASOURCEISH',
        'SPRING_DATASOURCE_APIKEY',
        'SPRING_DATASOURCE_PASSWORD',
        'app.a_b',
        'app.secret-key',
        'app.servers[0].host',
        'app.servers[1].host',
        'debug',
        'spring.dataSource.apiKey',
        'spring.datasource.password',
        'spring.datasourceish',
      ];
      List<String> left(List<String> prefixes) =>
          DartDefineKeys.without(keys, prefixes);
      const datasource = [
        'SPRING_DATASOURCE_APIKEY',
        'SPRING_DATASOURCE_PASSWORD',
        'spring.dataSource.apiKey',
        'spring.datasource.password',
      ];

      test('the environment form of a prefix covers the dotted form', () {
        expect(
          left(['SPRING_DATASOURCE']),
          isNot(anyElement(isIn(datasource))),
        );
        expect(left(['SPRING_DATASOURCE']), contains('spring.datasourceish'));
      });

      test('case-insensitive: spring.datasource leaves out dataSource', () {
        expect(
          left(['spring.datasource']),
          isNot(anyElement(isIn(datasource))),
        );
        expect(
          left(['spring.DATASOURCE']),
          isNot(anyElement(isIn(datasource))),
        );
      });

      test('a trailing . or [ is the same prefix, in both forms', () {
        for (final prefix in ['spring.datasource.', 'spring.datasource[']) {
          expect(left([prefix]), left(['spring.datasource']), reason: prefix);
        }
        expect(
          left(['spring.datasource']),
          containsAll(['spring.datasourceish', 'SPRING_DATASOURCEISH']),
        );
      });

      test('- and _ inside a segment are ignored', () {
        expect(
          left(['spring.data-source']),
          isNot(anyElement(isIn(datasource))),
        );
        expect(
          left(['spring.data_source']),
          isNot(anyElement(isIn(datasource))),
        );
        expect(
          left(['app.secretKey']),
          isNot(anyElement(isIn(['app.secret-key', 'APP_SECRETKEY']))),
        );
        expect(
          left(['app.secret-key']),
          isNot(anyElement(isIn(['app.secret-key', 'APP_SECRETKEY']))),
        );
      });

      test('the dotted and environment forms go together', () {
        // APP_A_B is the environment form of app.a_b, and under app.a.
        expect(
          left(['app.a']),
          isNot(anyElement(isIn(['app.a_b', 'APP_A_B']))),
        );
        expect(
          left(['app.a_b']),
          isNot(anyElement(isIn(['app.a_b', 'APP_A_B']))),
        );
        expect(
          left(['APP_A_B']),
          isNot(anyElement(isIn(['app.a_b', 'APP_A_B']))),
        );
      });

      test('indexes are segments', () {
        expect(
          left(['app.servers[0]']),
          isNot(
            anyElement(isIn(['app.servers[0].host', 'APP_SERVERS_0_HOST'])),
          ),
        );
        expect(left(['app.servers[0]']), contains('app.servers[1].host'));
        expect(
          left(['APP_SERVERS']),
          isNot(
            anyElement(
              isIn([
                'APP_SERVERS_0_HOST',
                'app.servers[0].host',
                'app.servers[1].host',
              ]),
            ),
          ),
        );
      });

      test('whole segments only', () {
        expect(left(['spring.data']), keys);
        expect(left(['app.secret']), keys);
        expect(left(['debu']), keys);
        expect(left(['debug']), isNot(anyElement(isIn(['debug', 'DEBUG']))));
      });
    });

    test('the dart_defines_exclude option', () {
      List<String> parsed(Object? option) => (springCoreDartBuilder(
        BuilderOptions({'dart_defines_exclude': option}),
      ) as SpringBuilder).dartDefinesExclude;
      expect(parsed(null), isEmpty);
      expect(parsed(<Object>[]), isEmpty);
      expect(
        parsed([' spring.datasource. ', 'app.servers[', 'SPRING_X..']),
        ['spring.datasource', 'app.servers', 'SPRING_X'],
      );
      for (final invalid in <Object>[
        'spring.datasource',
        {'spring': true},
        [1],
        [null],
        [''],
        ['   '],
        ['.'],
        ['*'],
        ['spring.datasource.*'],
        ['spring.*.password'],
        ['spring datasource'],
      ]) {
        expect(
          () => parsed(invalid),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.name,
              'name',
              'dart_defines_exclude',
            ),
          ),
          reason: '$invalid',
        );
      }
    });

    test('always includes profiles and the OS environment switch', () {
      expect(
        DartDefineKeys().keys,
        containsAll([
          'spring.profiles.active',
          'SPRING_PROFILES_ACTIVE',
          'spring.flutter.scan-os-environment',
          'SPRING_FLUTTER_SCANOSENVIRONMENT',
        ]),
      );
    });
  });

  test('springApplication lists the keys as const fromEnvironment', () async {
    final (_, output) = await _build();
    expect(output, contains('dartDefines: {'));
    final flat = output.replaceAll(RegExp(r'\s'), '');
    String entry(String key) =>
        "if(constbool.hasEnvironment('$key'))"
        "'$key':constString.fromEnvironment('$key'";
    for (final key in [
      'API_URL', // @Value placeholder
      'api.fallback-url', // nested default + config file key
      'API_FALLBACKURL',
      'api.timeout', // @ConfigurationProperties field
      'API_TIMEOUT',
      'api.retry.max-attempts', // nested properties class
      'feature.beta.enabled', // @ConditionalOnProperty
      'FEATURE_BETA_ENABLED',
      'shop.owner', // placeholder in a config file
      'cache.ttl', // YAML key
      'hosts[1]',
      'HOST_B',
      'SPRING_PROFILES_ACTIVE',
    ]) {
      expect(flat, contains(entry(key)), reason: key);
    }
    expect(output, isNot(contains("'not.read'")));
  });

  test('defines reach the running application (dart -D)', () async {
    final (sources, output) = await _build();
    final directory = await Directory.systemTemp.createTemp('spring_define_');
    addTearDown(() => directory.delete(recursive: true));
    final files = {...sources, 'bin/spring_gen/main.spring.dart': output};
    for (final MapEntry(:key, :value) in files.entries) {
      final file = File('${directory.path}/$key');
      await file.parent.create(recursive: true);
      await file.writeAsString(value);
    }
    final workspace = await loadPackageConfigUri(
      (await Isolate.packageConfig)!,
    );
    await savePackageConfig(
      PackageConfig([
        ...workspace.packages,
        Package(
          'pkg',
          directory.uri,
          packageUriRoot: directory.uri.resolve('lib/'),
        ),
      ]),
      directory,
    );
    Future<Map<String, Object?>> run(List<String> defines) async {
      final process = await Process.run(Platform.resolvedExecutable, [
        ...defines,
        '--packages=${directory.path}/.dart_tool/package_config.json',
        '${directory.path}/bin/main.dart',
      ], workingDirectory: directory.path);
      final line = LineSplitter.split('${process.stdout}')
          .where((line) => line.startsWith('RESULT '))
          .firstOrNull;
      expect(line, isNotNull, reason: '${process.stdout}${process.stderr}');
      return jsonDecode(line!.substring('RESULT '.length))
          as Map<String, Object?>;
    }

    expect(await run(const []), {
      'url': 'https://fallback',
      'timeout': 1,
      'profiles': <Object?>[],
      'beta': false,
    });
    expect(
      await run(const [
        '-DAPI_URL=https://api.neon.books',
        '-DAPI_TIMEOUT=30',
        '-DSPRING_PROFILES_ACTIVE=prod',
        '-Dfeature.beta.enabled=true',
        '-DNOT_KNOWN=1',
      ]),
      {
        'url': 'https://api.neon.books',
        'timeout': 30,
        'profiles': ['prod'],
        'beta': true,
      },
    );
  }, timeout: const Timeout.factor(4));
}
