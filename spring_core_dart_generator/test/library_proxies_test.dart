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
    final module = File(
      '../spring_boot_dart/lib/spring_gen/src/properties/properties.spring.dart',
    ).readAsStringSync();
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
