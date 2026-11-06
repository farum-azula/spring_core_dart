// The proxies of library beans: a starter's `lib/` module leaves the proxy
// class of a bean only the application's aspects can match to the
// application (`AopProxyFactory.deferred`); the `@SpringBootApplication`
// output writes it when one of its pointcuts may match the bean, and the
// context puts it in the placeholder's place.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart' show AssetId;
import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _main = r'''
import 'dart:convert';

import 'package:spring_boot_dart/spring_boot_dart.dart';
// The library's properties classes, which it does not export.
import 'package:spring_boot_dart/src/properties/boot_properties.dart';
import 'package:pkg/app.dart';

import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) {
  final context = runApplication([
    '--spring.main.banner-mode=off',
    '--logging.level.root=off',
    '--spring.main.web-application-type=none',
  ]);
  final banner = context.getBean<BannerProperties>();
  final main = context.getBean<MainProperties>();
  banner.location;
  print('RESULT ${jsonEncode({
    'bannerAdvised': banner is Advised,
    'mainAdvised': main is Advised,
    'calls': context.getBean<BannerAudit>().calls,
  })}');
  context.close();
}
''';

const _app = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@Aspect()
@Component()
class BannerAudit {
  final calls = <String>[];

  @Before('within(BannerProperties)')
  void audit(JoinPoint joinPoint) => calls.add(joinPoint.signature.name);
}
''';

Future<(Map<String, String>, String)> _build({
  String app = _app,
  String main = _main,
  Map<String, String> starter = const {},
  Map<String, String> library = const {},
}) async {
  final sources = {'lib/app.dart': app, 'bin/main.dart': main};
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  for (final MapEntry(:key, :value) in starter.entries) {
    readerWriter.testing.writeString(AssetId('starter', key), value);
  }
  for (final MapEntry(:key, :value) in library.entries) {
    readerWriter.testing.writeString(AssetId('library', key), value);
  }
  final workspace = await loadPackageConfigUri((await Isolate.packageConfig)!);
  final result = await testBuilder(
    SpringBuilder(),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
    packageConfig: starter.isEmpty
        ? null
        : PackageConfig([
            ...workspace.packages,
            Package('pkg', Uri.parse('file:///pkg/')),
            Package('starter', Uri.parse('file:///starter/')),
            if (library.isNotEmpty)
              Package('library', Uri.parse('file:///library/')),
          ]),
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
  test('the library module keeps the signatures, not the class', () {
    const path =
        'spring_boot_dart/lib/spring_gen/src/properties/properties.spring.dart';
    // From the generator's folder or the repository's root (the workspace
    // run).
    final module = [
      File('../$path'),
      File(path),
    ].firstWhere((f) => f.existsSync()).readAsStringSync();
    expect(module, contains('AopProxyFactory.deferred('));
    expect(module, isNot(contains(r'class _$BannerPropertiesProxy')));
  });

  test(
    'the application writes only the proxies its pointcuts may match',
    () async {
      final (_, output) = await _build();
      expect(output, contains(r'class _$BannerPropertiesProxy'));
      expect(output, isNot(contains(r'class _$MainPropertiesProxy')));
      expect(
        output.replaceAll(RegExp(r'\s'), ''),
        contains(
          "aopProxies:{r'package:spring_boot_dart/src/properties/"
          "boot_properties.dart#BannerProperties':_i",
        ),
      );
    },
  );

  test('without an aspect on them, nothing of the library beans', () async {
    final (_, output) = await _build(
      app: "import 'package:spring_boot_dart/spring_boot_dart.dart';\n",
    );
    expect(output, isNot(contains('aopProxies')));
    expect(output, isNot(contains(r'_$BannerPropertiesProxy')));
  });

  test('a bean(...) pointcut matches the alias of a library bean', () async {
    // A starter whose module left the proxy of an aliased bean to the
    // application.
    const starter = {
      'lib/spring_auto_configuration.dart': r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:starter/spring_gen/beans.spring.dart';

@AutoConfigurationModule()
final BeanModule starterAutoConfiguration = BeanModule(
  'starterAutoConfiguration',
  const [],
  imports: [$starterBeans],
);
''',
      'lib/task.dart': 'class Task { void run() {} }',
      'lib/spring_gen/beans.spring.dart': r"""
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:starter/task.dart';

BeanModule get $starterBeans => BeanModule(r'starterBeans', [
  BeanDefinition<Task>(
    name: r'task',
    source: r'package:starter/task.dart#Task',
    aliases: const [r'taskExecutor'],
    qualifiers: const {r'background'},
    create: (r) => Task(),
    aopProxy: const AopProxyFactory.deferred(signatures: []),
  ),
]);
""",
    };
    const main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:pkg/app.dart';

import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main() => runApplication();
''';
    String app(String pointcut) =>
        '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@Aspect()
@Component()
class TaskAudit {
  @Before('$pointcut')
  void audit(JoinPoint joinPoint) {}
}
''';
    for (final name in ['taskExecutor', 'background']) {
      final (_, output) = await _build(
        app: app('bean($name)'),
        main: main,
        starter: starter,
      );
      expect(output, contains(r'class _$TaskProxy'), reason: name);
    }
    final (_, output) = await _build(
      app: app('bean(other)'),
      main: main,
      starter: starter,
    );
    expect(output, isNot(contains(r'_$TaskProxy')));
  });

  test(
    'a deferred bean of a library without an auto-configuration is found '
    "through a starter's auto-configuration and the library's exports",
    () async {
      // spring_boot_actuator's shape: the library's main library exports the
      // module; the starter's auto-configuration imports the main library.
      const library = {
        'lib/library.dart': "export 'src/settings.dart';",
        'lib/src/settings.dart': r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:library/spring_gen/src/settings.spring.dart';

@ComponentScan()
final BeanModule librarySettings = $librarySettings;

class Settings {
  void load() {}
}
''',
        'lib/spring_gen/src/settings.spring.dart': r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:library/src/settings.dart';

BeanModule get $librarySettings => BeanModule(r'librarySettings', [
  BeanDefinition<Settings>(
    name: r'settings',
    source: r'package:library/src/settings.dart#Settings',
    create: (r) => Settings(),
    aopProxy: const AopProxyFactory.deferred(signatures: []),
  ),
]);
''',
      };
      const starter = {
        'lib/spring_auto_configuration.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:library/library.dart';

@AutoConfigurationModule()
final BeanModule starterAutoConfiguration = BeanModule(
  'starterAutoConfiguration',
  const [],
  imports: [librarySettings],
);
''',
      };
      const main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:pkg/app.dart';

import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main() => runApplication();
''';
      const app = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@Aspect()
@Component()
class SettingsAudit {
  @Before('bean(settings)')
  void audit(JoinPoint joinPoint) {}
}
''';
      final (_, output) = await _build(
        app: app,
        main: main,
        starter: starter,
        library: library,
      );
      expect(output, contains(r'class _$SettingsProxy'));
      expect(
        output.replaceAll(RegExp(r'\s'), ''),
        contains("r'package:library/src/settings.dart#Settings':_i"),
      );
    },
  );

  // A library without an auto-configuration: with `aop_defer` (a starter
  // imports its modules) it defers like a starter; without, it keeps every
  // proxy, since any module may import it.
  for (final defer in [true, false]) {
    test(
      'a library without an auto-configuration, aop_defer: $defer',
      () async {
        final readerWriter = TestReaderWriter(
          rootPackage: 'pkg',
          flattenOutput: true,
        );
        await readerWriter.testing.loadIsolateSources();
        final result = await testBuilder(
          SpringBuilder(deferProxies: defer),
          {
            'pkg|lib/src/settings.dart': r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:pkg/spring_gen/src/settings.spring.dart';

@ComponentScan()
final BeanModule settingsBeans = $settingsBeans;

@Component()
class Settings {
  String get name => 'settings';
}
''',
          },
          rootPackage: 'pkg',
          readerWriter: readerWriter,
          flattenOutput: true,
        );
        expect(result.errors, isEmpty);
        final output = readerWriter.testing.readString(
          result.outputs.singleWhere(
            (o) => o.path == 'lib/spring_gen/src/settings.spring.dart',
          ),
        );
        expect(output.contains('AopProxyFactory.deferred('), defer);
        expect(output.contains(r'class _$SettingsProxy'), !defer);
      },
    );
  }

  test('an annotation an advisor of the application names keeps the members '
      'of a library bean', () async {
    // The starter's module left the proxy of Task to the application; the
    // application's advisor matches its @Tag member by annotation.
    const starter = {
      'lib/spring_auto_configuration.dart': r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:starter/spring_gen/beans.spring.dart';

@AutoConfigurationModule()
final BeanModule starterAutoConfiguration = BeanModule(
  'starterAutoConfiguration',
  const [],
  imports: [$starterBeans],
);
''',
      'lib/task.dart': '''
class Tag {
  const Tag();
}

class Task {
  @Tag()
  void run() {}
  void other() {}
}
''',
      'lib/spring_gen/beans.spring.dart': r"""
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:starter/task.dart';

BeanModule get $starterBeans => BeanModule(r'starterBeans', [
  BeanDefinition<Task>(
    name: r'task',
    source: r'package:starter/task.dart#Task',
    create: (r) => Task(),
    aopProxy: const AopProxyFactory.deferred(signatures: []),
  ),
]);
""",
    };
    const main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:pkg/app.dart';

import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main() => runApplication();
''';
    const app = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:starter/task.dart';

class Guard implements MethodInterceptor {
  const Guard();
  @override
  Object? invoke(MethodInvocation invocation) => invocation.proceed();
}

@Configuration()
class Guards {
  @Bean()
  PointcutAdvisor guard() => DefaultPointcutAdvisor(
    const AnnotationMatchingPointcut<Tag>(),
    const Guard(),
  );
}
''';
    final (_, output) = await _build(app: app, main: main, starter: starter);
    final normalized = output.replaceAll(RegExp(r'\b_i\d+\.|\s'), '');
    expect(output, contains(r'class _$TaskProxy'));
    expect(normalized, contains("MethodSignature.of(r'run',"));
    // A partial proxy: the context knows which advisors it was made for.
    expect(normalized, contains('voidother()=>this._target.other();'));
    expect(normalized, contains(r'knownAdvisors:_$knownAdvisors'));
  });

  group("a starter's module", () {
    // A starter (a library package with an auto-configuration library)
    // with a bean in one module and, maybe, an aspect in another.
    Future<String> settingsModule({required bool aspect}) async {
      final readerWriter = TestReaderWriter(
        rootPackage: 'pkg',
        flattenOutput: true,
      );
      await readerWriter.testing.loadIsolateSources();
      final result = await testBuilder(
        SpringBuilder(),
        {
          // Imports the modules, as a starter's does: the build of one
          // does not read the module being built.
          'pkg|lib/spring_auto_configuration.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:pkg/src/config/config.dart';
import 'package:pkg/src/settings/settings.dart';

@AutoConfigurationModule()
final BeanModule pkgAutoConfiguration = BeanModule(
  'pkgAutoConfiguration',
  const [],
  imports: [configBeans, settingsBeans],
);
''',
          'pkg|lib/src/settings/settings.dart': r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:pkg/spring_gen/src/settings/settings.spring.dart';

@ComponentScan()
final BeanModule settingsBeans = $settingsBeans;

@Component()
class Settings {
  String get name => 'settings';
}
''',
          'pkg|lib/src/config/config.dart': r'''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:pkg/spring_gen/src/config/config.spring.dart';

@ComponentScan()
final BeanModule configBeans = $configBeans;
''',
          if (aspect)
            'pkg|lib/src/config/audit.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@Aspect()
@Component()
class SettingsAudit {
  @Before('within(Settings)')
  void audit() {}
}
''',
        },
        rootPackage: 'pkg',
        readerWriter: readerWriter,
        flattenOutput: true,
      );
      expect(result.errors, isEmpty);
      return readerWriter.testing.readString(
        result.outputs.singleWhere(
          (o) => o.path == 'lib/spring_gen/src/settings/settings.spring.dart',
        ),
      );
    }

    test('defers a proxy no advice of the package matches', () async {
      final output = await settingsModule(aspect: false);
      expect(output, contains('AopProxyFactory.deferred('));
      expect(output, isNot(contains(r'class _$SettingsProxy')));
    });

    test('keeps one an aspect of another module matches', () async {
      // A context of the starter's modules alone (ApplicationContextRunner)
      // applies the aspect: the proxy class must be there.
      final output = await settingsModule(aspect: true);
      expect(output, isNot(contains('AopProxyFactory.deferred(')));
      expect(output, contains(r'class _$SettingsProxy'));
    });
  });

  test('the advice runs on the library bean', () async {
    final (sources, output) = await _build();
    final directory = await Directory.systemTemp.createTemp('spring_proxy_');
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
    final process = await Process.run(Platform.resolvedExecutable, [
      '--packages=${directory.path}/.dart_tool/package_config.json',
      '${directory.path}/bin/main.dart',
    ], workingDirectory: directory.path);
    final line = LineSplitter.split(
      '${process.stdout}',
    ).where((line) => line.startsWith('RESULT ')).firstOrNull;
    expect(line, isNotNull, reason: '${process.stdout}${process.stderr}');
    expect(jsonDecode(line!.substring('RESULT '.length)), {
      'bannerAdvised': true,
      'mainAdvised': false,
      'calls': ['location'],
    });
  }, timeout: const Timeout.factor(4));
}
