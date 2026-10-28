@TestOn('vm')
library;

import 'dart:io';

import 'package:spring_boot_starter_logging/spring_auto_configuration.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:test/test.dart';

final class Store {}

final class Broken {
  Broken() {
    throw StateError('no database');
  }
}

void main() {
  late Directory dir;
  final console = <String>[];
  final system = LoggingSystem.instance;
  late SpringLogLevel savedLevel;

  setUp(() {
    savedLevel = SpringLog.level;
    dir = Directory.systemTemp.createTempSync('spring_failure_');
    console.clear();
    system.console.out = console.add;
  });
  tearDown(() {
    SpringLog.level = savedLevel;
    dir.deleteSync(recursive: true);
  });

  SpringApplication application(BeanDefinition<Object> bean) =>
      SpringApplication(
        [
          BeanModule('app', [bean]),
        ],
        autoConfigurations: [springBootStarterLoggingAutoConfiguration],
        bannerMode: BannerMode.off,
      );

  List<String> properties() => [
    '--logging.file.name=${dir.path}/app.log',
    '--logging.pattern.file=%p %logger %m%n%ex',
    '--logging.pattern.console=%p %m',
    '--spring.output.ansi.enabled=never',
  ];

  String file() => File('${dir.path}/app.log').readAsStringSync();

  test('a failure without analysis is logged, to the file too', () async {
    final previous = SpringLog.handler;
    expect(
      () => application(
        BeanDefinition<Broken>(name: 'broken', create: (_) => Broken()),
      ).run(properties(), systemEnvironment: const {}),
      throwsA(anything),
    );
    expect(console, contains(startsWith('ERROR Application run failed')));
    // Uninstalled (the file closed) once the failure is logged.
    expect(system.isInstalled, isTrue);
    await pumpEventQueue();
    expect(system.isInstalled, isFalse);
    expect(
      file(),
      contains(
        'ERROR spring_boot_dart.SpringApplication Application run failed',
      ),
    );
    expect(file(), contains('no database'));
    expect(SpringLog.handler, previous);
  });

  test('a failure analysis reaches the file (runAsync)', () async {
    await expectLater(
      application(
        BeanDefinition<Store>(
          name: 'store',
          dependencies: const [Dependency(Broken)],
          create: (_) => Store(),
        ),
      ).runAsync(properties(), systemEnvironment: const {}),
      throwsA(anything),
    );
    await pumpEventQueue();
    expect(system.isInstalled, isFalse);
    expect(
      file(),
      contains(
        'ERROR spring_boot_dart.diagnostics.LoggingFailureAnalysisReporter',
      ),
    );
    expect(file(), contains('APPLICATION FAILED TO START'));
  });

  test('a normal close still uninstalls at once', () {
    application(BeanDefinition<Store>(name: 'store', create: (_) => Store()))
        .run(properties(), systemEnvironment: const {})
        .close();
    expect(system.isInstalled, isFalse);
  });
}
