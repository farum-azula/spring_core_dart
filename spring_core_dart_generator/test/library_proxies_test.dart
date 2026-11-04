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

Future<(Map<String, String>, String)> _build({String app = _app}) async {
  final sources = {'lib/app.dart': app, 'bin/main.dart': _main};
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
