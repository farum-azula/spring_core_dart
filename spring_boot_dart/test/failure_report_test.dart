import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

final class Broken {
  Broken() {
    throw StateError('no database');
  }
}

final class Store {}

SpringApplication _app(BeanDefinition<Object> bean, {List<String>? out}) =>
    SpringApplication(
      [
        BeanModule('app', [bean]),
      ],
      bannerMode: BannerMode.off,
      out: out?.add,
    );

final _broken = BeanDefinition<Broken>(name: 'broken', create: (_) => Broken());

final _unsatisfied = BeanDefinition<Store>(
  name: 'store',
  dependencies: const [Dependency(Broken)],
  create: (_) => Store(),
);

void main() {
  late List<SpringLogRecord> records;
  late void Function() stop;
  setUp(() {
    records = [];
    stop = SpringLog.listen(records.add);
  });
  tearDown(() => stop());

  test('a refresh failure without analysis is logged with its stack trace '
      'as "Application run failed"', () {
    expect(
      () => _app(_broken).run(const [], systemEnvironment: const {}),
      throwsA(isA<Object>()),
    );
    final record = records.singleWhere(
      (r) => r.message == 'Application run failed',
    );
    expect(record.level, SpringLogLevel.error);
    expect(record.loggerName, 'spring_boot_dart.SpringApplication');
    expect('${record.error}', contains('no database'));
    expect(record.stackTrace, isNotNull);
  });

  test('a failure analysis is logged by LoggingFailureAnalysisReporter '
      '(runAsync)', () async {
    await expectLater(
      _app(_unsatisfied).runAsync(const [], systemEnvironment: const {}),
      throwsA(isA<Object>()),
    );
    final record = records.singleWhere(
      (r) =>
          r.loggerName ==
          'spring_boot_dart.diagnostics.LoggingFailureAnalysisReporter',
    );
    expect(record.level, SpringLogLevel.error);
    expect(record.message, contains('APPLICATION FAILED TO START'));
  });

  test('with out: the reports go there instead of the log', () {
    final lines = <String>[];
    expect(
      () =>
          _app(_broken, out: lines).run(const [], systemEnvironment: const {}),
      throwsA(isA<Object>()),
    );
    expect(lines.single, startsWith('Application run failed: '));
    expect(lines.single, contains('no database'));
    expect(records.where((r) => r.level == SpringLogLevel.error), isEmpty);
  });

  test('DeferredLogs collects what is logged during the start', () {
    final context = _app(
      BeanDefinition<Store>(name: 'store', create: (_) => Store()),
    ).run(const [], systemEnvironment: const {});
    addTearDown(context.close);
    final deferred = context.getBean<DeferredLogs>();
    // Switched over once the context is refreshed.
    expect(deferred.isCapturing, isFalse);
    expect(deferred.switchOver(), isEmpty);
  });
}
