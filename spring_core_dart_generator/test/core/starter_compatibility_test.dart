import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart' show springBootVersion;
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _app = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''';

String _starter(String requires, [String arguments = '']) =>
    '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@AutoConfigurationModule(requires: '$requires'$arguments)
final BeanModule neonCacheAutoConfiguration = BeanModule('neonCache', []);
''';

/// Builds an application depending on a fake `neon_cache` starter.
Future<TestBuilderResult> _build(
  String requires, {
  String app = _app,
  String arguments = '',
  String? config,
  String configFile = 'application.properties',
  String? starter,
  List<String>? logs,
}) async {
  final isolateConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  final packageConfig = PackageConfig([
    ...isolateConfig.packages,
    Package(
      'neon_cache',
      Uri.parse('file:///neon_cache/'),
      packageUriRoot: Uri.parse('file:///neon_cache/lib/'),
    ),
  ]);
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  return await testBuilder(
    SpringBuilder(),
    {
      'pkg|bin/main.dart': app,
      'pkg|lib/resources/$configFile': ?config,
      'neon_cache|lib/spring_auto_configuration.dart':
          starter ?? _starter(requires, arguments),
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: packageConfig,
    flattenOutput: true,
    onLog: logs == null
        ? null
        : (record) => logs.add('${record.level.name}: ${record.message}'),
  );
}

void main() {
  group('build: AutoConfigurationBuild(property) decides at build time', () {
    const build = ", build: AutoConfigurationBuild('neon.debug.enabled')";

    Future<String> output({String? config, String arguments = build}) async {
      final result = await _build(
        '^$springBootVersion',
        arguments: arguments,
        config: config,
      );
      expect(result.errors, isEmpty);
      return _compact(result);
    }

    test('true: the module, always', () async {
      final code = await output(config: 'neon.debug.enabled=true');
      expect(code, matches(RegExp(r'[\[,]_i\d+\.neonCacheAutoConfiguration,')));
      expect(code, isNot(contains('dart.vm.product')));
    });

    test('false: no module, no code', () async {
      final code = await output(config: 'neon.debug.enabled=false');
      expect(code, isNot(contains('neonCacheAutoConfiguration')));
    });

    test('not set: only outside a release', () async {
      final code = await output();
      expect(
        code,
        matches(
          RegExp(
            r"if\(!constbool\.fromEnvironment\('dart\.vm\.product'\)\)"
            r'_i\d+\.neonCacheAutoConfiguration',
          ),
        ),
      );
    });

    test('set only in a profile: a warning, built as when not set', () async {
      for (final (file, config) in [
        ('application-web.yml', 'neon:\n  debug:\n    enabled: false\n'),
        ('application-web.yml', 'neon.debug:\n  enabled: false\n'),
        ('application-web.properties', 'neon.debug.enabled=false\n'),
      ]) {
        final logs = <String>[];
        final result = await _build(
          '^$springBootVersion',
          arguments: build,
          config: config,
          configFile: file,
          logs: logs,
        );
        expect(result.errors, isEmpty);
        expect(
          logs,
          contains(
            allOf(
              startsWith('WARNING: '),
              contains('neon_cache.neonCacheAutoConfiguration: '),
              contains('neon.debug.enabled is set only in $file'),
            ),
          ),
          reason: '$file: $config',
        );
        expect(_compact(result), contains("dart.vm.product'))_i"));
      }
    });

    test('a value the build cannot read fails, naming the module', () async {
      final result = await _build(
        '^$springBootVersion',
        arguments: build,
        config: r'neon.debug.enabled=${FLAG}',
      );
      expect(
        result.errors.join(),
        allOf(
          contains('neon_cache.neonCacheAutoConfiguration'),
          contains('neon.debug.enabled'),
          contains("'FLAG'"),
        ),
      );
    });

    test('set without a profile: no warning', () async {
      final logs = <String>[];
      await _build(
        '^$springBootVersion',
        arguments: build,
        config: 'neon.debug.enabled=false',
        logs: logs,
      );
      expect(logs.where((log) => log.contains('set only in')), isEmpty);
    });

    test('not set, whenMissing: never', () async {
      final code = await output(
        arguments:
            ", build: AutoConfigurationBuild('neon.debug.enabled', "
            'whenMissing: BuildInclusion.never)',
      );
      expect(code, isNot(contains('neonCacheAutoConfiguration')));
    });
  });

  group('platform: the module only where its code works', () {
    Future<String> output(String arguments, {String? config}) async {
      final result = await _build(
        '^$springBootVersion',
        arguments: arguments,
        config: config,
      );
      expect(result.errors, isEmpty);
      return _compact(result);
    }

    test('native: under dart.library.io', () async {
      final code = await output(', platform: ModulePlatform.native');
      expect(
        code,
        matches(
          RegExp(
            r"if\(\(constbool\.fromEnvironment\('dart\.library\.io'\)\|\|"
            r"constbool\.fromEnvironment\('SPRING_ALL_PLATFORMS'\)\)\)"
            r'_i\d+\.neonCacheAutoConfiguration',
          ),
        ),
      );
      expect(code, isNot(contains('dart.vm.product')));
    });

    test('web: under dart.library.js_interop', () async {
      final code = await output(', platform: ModulePlatform.web');
      expect(
        code,
        matches(
          RegExp(
            r"if\(\(constbool\.fromEnvironment\('dart\.library\.js_interop'\)"
            r"\|\|constbool\.fromEnvironment\('SPRING_ALL_PLATFORMS'\)\)\)"
            r'_i\d+\.neonCacheAutoConfiguration',
          ),
        ),
      );
    });

    test('with a build property not set: both conditions', () async {
      final code = await output(
        ", build: AutoConfigurationBuild('neon.debug.enabled'), "
        'platform: ModulePlatform.native',
      );
      expect(
        code,
        contains(
          "if(!constbool.fromEnvironment('dart.vm.product')&&"
          "(constbool.fromEnvironment('dart.library.io')||"
          "constbool.fromEnvironment('SPRING_ALL_PLATFORMS')))",
        ),
      );
    });

    test('with a build property false: no module', () async {
      final code = await output(
        ", build: AutoConfigurationBuild('neon.debug.enabled'), "
        'platform: ModulePlatform.native',
        config: 'neon.debug.enabled=false',
      );
      expect(code, isNot(contains('neonCacheAutoConfiguration')));
    });

    test('its order stays, under the same condition', () async {
      final code = await output(', order: 5, platform: ModulePlatform.native');
      expect(
        code,
        matches(
          RegExp(
            r'autoConfigurationMetadata:\{if\(\(constbool\.fromEnvironment\('
            r"'dart\.library\.io'\)\|\|constbool\.fromEnvironment\("
            r"'SPRING_ALL_PLATFORMS'\)\)\)_i\d+\.neonCacheAutoConfiguration:"
            r'const_i\d+\.AutoConfigurationModule\(order:5,?\)',
          ),
        ),
      );
    });
  });

  test('a compatible starter is discovered', () async {
    final result = await _build('^$springBootVersion');
    expect(result.errors, isEmpty);
    final output = result.readerWriter.testing.readString(
      result.outputs.single,
    );
    expect(output, contains('neonCacheAutoConfiguration'));
  });

  test('an incompatible starter stops the build with an explanation', () async {
    // The next breaking version of today's (0.4.0 → 0.5.0): never compatible,
    // whatever the release bumps to.
    final incompatible = '^${Version.parse(springBootVersion).nextBreaking}';
    final result = await _build(incompatible);
    expect(result.succeeded, isFalse);
    final errors = result.errors.join('\n');
    expect(
      errors,
      contains(
        'Incompatible starter: neon_cache requires spring_boot_dart '
        '$incompatible',
      ),
    );
    expect(errors, contains('but $springBootVersion is used'));
  });

  test('an invalid range is reported', () async {
    final result = await _build('not a range');
    expect(
      result.errors.join('\n'),
      contains("invalid requires 'not a range'"),
    );
  });

  test(
    'order, before and after of a starter reach SpringApplication',
    () async {
      final result = await _build(
        '^$springBootVersion',
        arguments: ", order: 5, before: ['a'], after: ['b', 'c']",
      );
      expect(result.errors, isEmpty);
      expect(
        _compact(result),
        matches(
          RegExp(
            // Other starters of the workspace (the security starter)
            // have constraints of their own in the same map.
            r'autoConfigurationMetadata:\{_i\d+\.neonCacheAutoConfiguration:'
            r"const_i\d+\.AutoConfigurationModule\(order:5,before:\[r'a'\],"
            r"after:\[r'b',r'c'\],\),",
          ),
        ),
      );
    },
  );

  test('the factories of a starter reach SpringApplication as the constants '
      'they were written as', () async {
    final result = await _build(
      '^$springBootVersion',
      starter: '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

class Design {
  const Design([this.name = 'plain', this.dense = false]);
  const Design.named({required this.name}) : dense = true;
  final String name;
  final bool dense;
  static const ocean = Design('ocean');
}

const forest = Design('forest');

@AutoConfigurationModule(
  factories: [
    Design(),
    Design('neon', true),
    Design.named(name: 'named'),
    Design.ocean,
    forest,
  ],
)
final BeanModule neonCacheAutoConfiguration = BeanModule('neonCache', []);
''',
    );
    expect(result.errors, isEmpty);
    // The constants come from the starter's package, not a file path.
    expect(_compact(result), isNot(contains("import'asset:")));
    expect(
      _compact(result),
      matches(
        RegExp(
          r'_i\d+\.neonCacheAutoConfiguration:'
          r'const_i\d+\.AutoConfigurationModule\(factories:\['
          r'_i\d+\.Design\(\),'
          r"_i\d+\.Design\('neon',true,?\),"
          r"_i\d+\.Design\.named\(name:'named',?\),"
          r'_i\d+\.Design\.ocean,'
          r"_i\d+\.Design\('forest',?\),\]",
        ),
      ),
    );
  });

  test('a factory that is no public constant stops the build', () async {
    final result = await _build(
      '^$springBootVersion',
      starter: '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

class _Hidden {
  const _Hidden();
}

@AutoConfigurationModule(factories: [_Hidden()])
final BeanModule neonCacheAutoConfiguration = BeanModule('neonCache', []);
''',
    );
    expect(result.succeeded, isFalse);
    expect(
      result.errors.join('\n'),
      contains('A factory is a public constant'),
    );
  });

  test('a starter without constraints adds no metadata', () async {
    final result = await _build('^$springBootVersion');
    // The workspace's own starters may have some (the security starter);
    // the test starter has none.
    expect(
      _compact(result),
      isNot(contains('neonCacheAutoConfiguration:const')),
    );
  });

  test(
    'exclude and excludeName of @SpringBootApplication are passed on',
    () async {
      final result = await _build(
        '^$springBootVersion',
        app: r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

class CacheAutoConfiguration {}

@SpringBootApplication(
  exclude: [CacheAutoConfiguration],
  excludeName: ['neonCache', r'a$b', r'c\'],
)
void main(List<String> args) => runApplication(args);
''',
      );
      expect(result.errors, isEmpty);
      final output = _compact(result);
      expect(
        output,
        matches(RegExp(r'exclude:\[_i\d+\.CacheAutoConfiguration\]')),
      );
      // Raw: a name is text, whatever it has in it.
      expect(
        output,
        contains(r"excludeName:[r'neonCache',r'a$b',r'c\'"),
      );
    },
  );
}

// The generated source without whitespace.
String _compact(TestBuilderResult result) => result.readerWriter.testing
    .readString(result.outputs.single)
    .replaceAll(RegExp(r'\s+'), '');
