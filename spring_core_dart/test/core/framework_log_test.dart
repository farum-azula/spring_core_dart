import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

class Greeter {
  bool destroyed = false;
}

class Closer implements DisposableBean {
  @override
  void destroy() {}
}

AnnotationConfigApplicationContext context({List<String> profiles = const []}) {
  final environment = StandardEnvironment(systemEnvironment: {});
  if (profiles.isNotEmpty) {
    environment.setActiveProfiles(profiles);
  }
  return AnnotationConfigApplicationContext(
    [
      BeanModule('test', [
        BeanDefinition<Greeter>(name: 'greeter', create: (_) => Greeter()),
        BeanDefinition<Closer>(name: 'closer', create: (_) => Closer()),
      ]),
    ],
    environment: environment,
  );
}

void main() {
  late SpringLogLevel savedLevel;
  late SpringLogHandler savedHandler;
  final records = <SpringLogRecord>[];

  setUp(() {
    savedLevel = SpringLog.level;
    savedHandler = SpringLog.handler;
    records.clear();
    SpringLog.handler = records.add;
  });

  tearDown(() {
    SpringLog.level = savedLevel;
    SpringLog.handler = savedHandler;
    SpringLog.resetLevels();
  });

  List<String> messages(SpringLogLevel level) => [
    for (final r in records)
      if (r.level == level) r.message,
  ];

  test('the container logs nothing at info', () {
    context(profiles: ['dev'])
      ..refresh()
      ..publishEvent('x')
      ..close();
    expect(records, isEmpty);
  });

  test('debug: beans, refresh, close, profiles', () {
    SpringLog.level = SpringLogLevel.debug;
    final ctx = context(profiles: ['dev'])
      ..refresh()
      ..close();
    final debug = messages(SpringLogLevel.debug);
    expect(
      debug,
      containsAll([
        'Refreshing ${ctx.displayName}',
        'Closing ${ctx.displayName}',
        "Creating shared instance of singleton bean 'greeter'",
        'Activating profiles ["dev"]',
      ]),
    );
    expect(records.where((r) => r.level == SpringLogLevel.trace), isEmpty);
    expect(
      records.where((r) => r.loggerName == 'spring_core_dart.beans'),
      isNotEmpty,
    );
  });

  test('trace: creation steps, destroy callbacks, events', () {
    SpringLog.level = SpringLogLevel.trace;
    context()
      ..refresh()
      ..close();
    expect(
      messages(SpringLogLevel.trace),
      containsAll([
        "Creating instance of bean 'greeter'",
        "Finished creating instance of bean 'greeter'",
        'Pre-instantiating singletons in DefaultListableBeanFactory',
        'Destroying singletons in DefaultListableBeanFactory',
        "Invoking destroy() on bean with name 'closer'",
        contains('Publishing event in '),
        contains('ContextRefreshedEvent'),
      ]),
    );
  });

  test('the levels follow the logger names', () {
    SpringLog.setLevel('spring_core_dart.beans', SpringLogLevel.trace);
    context()
      ..refresh()
      ..close();
    expect(
      records.map((r) => r.loggerName).toSet().difference({
        'spring_core_dart.beans',
        'spring_core_dart.beans.factory.support.DisposableBeanAdapter',
      }),
      isEmpty,
    );
    expect(records, isNotEmpty);
  });

  test('config files: loaded at debug, the name quoted and cleaned; '
      'no values', () async {
    final dir = Directory.systemTemp.createTempSync('framework_log');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/a.properties')
      ..writeAsStringSync('secret=hunter2\n');
    final environment = StandardEnvironment(systemEnvironment: {})
      ..propertySources.addFirst(
        MapPropertySource('cli', {
          'spring.config.import':
              'file:${file.path},optional:file:${dir.path}/none.properties',
        }),
      );
    SpringLog.level = SpringLogLevel.trace;
    await ConfigDataEnvironment(
      environment,
      defaultLocations: const [],
      loaders: const [PropertiesPropertySourceLoader()],
    ).processAndApply();
    expect(
      messages(SpringLogLevel.debug),
      contains('Loaded config file "file:${file.path}"'),
    );
    expect(
      messages(SpringLogLevel.trace),
      contains(startsWith('Skipping missing resource ')),
    );
    expect(records.map((r) => r.message).join(), isNot(contains('hunter2')));
  });

  test('config files are not logged at info', () async {
    final environment = StandardEnvironment(systemEnvironment: {});
    await ConfigDataEnvironment(
      environment,
      defaultLocations: const [],
      loaders: const [PropertiesPropertySourceLoader()],
    ).processAndApply();
    expect(records, isEmpty);
  });
}
