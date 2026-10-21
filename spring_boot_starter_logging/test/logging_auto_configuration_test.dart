import 'package:spring_boot_starter_logging/spring_auto_configuration.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

class CollectingAppender extends LogAppender {
  final messages = <String>[];

  @override
  void write(SpringLogRecord record) => messages.add(record.message);
}

class BrokenAppender extends LogAppender {
  @override
  void write(SpringLogRecord record) => throw StateError('broken');
}

const log = SpringLog('neon.shop');

void main() {
  final runner = const ApplicationContextRunner().withAutoConfiguration(
    springBootStarterLoggingAutoConfiguration,
  );
  final system = LoggingSystem.instance;
  final console = <String>[];
  late SpringLogLevel savedLevel;

  setUp(() {
    savedLevel = SpringLog.level;
    console.clear();
    system
      ..console.out = console.add
      ..console.pattern = LogPattern('%-5p [%logger] %m%X')
      ..buffer.clear();
  });
  tearDown(() {
    SpringLog.level = savedLevel;
    SpringLog.resetLevels();
  });

  test('installs the logging system behind SpringLog', () {
    final previous = SpringLog.handler;
    runner.run((context) {
      expect(context, hasSingleBean<LoggingSystem>());
      expect(context.getBean<LogBuffer>(), same(system.buffer));
      expect(system.isInstalled, isTrue);
      expect(SpringLog.level, SpringLogLevel.info); // Boot's default root

      log.info('order placed', fields: {'order': 7});
      log.debug('hidden');
    });
    expect(console, ['INFO  [neon.shop] order placed {order=7}']);
    expect(system.buffer.records.single.fields, {'order': 7});
    // Closing the context restores the previous handler.
    expect(system.isInstalled, isFalse);
    expect(SpringLog.handler, previous);
  });

  test('logging.* properties', () {
    SpringLog.setLevel('neon.shop', SpringLogLevel.debug);
    runner
        .withPropertyValues([
          'logging.level.root=warn',
          'logging.pattern.console=%p|%m',
          'logging.threshold.console=info',
          'logging.buffer.capacity=2',
          'logging.threshold.buffer=debug',
        ])
        .run((context) {
          expect(context.hasFailed, isFalse);
          // Root set: left to spring_boot_dart, not reset to info.
          expect(SpringLog.level, savedLevel);
          log
            ..debug('d1')
            ..info('i1')
            ..warning('w1');
        });
    expect(console, ['INFO|i1', 'WARN|w1']);
    expect(system.buffer.capacity, 2);
    expect(system.buffer.records.map((r) => r.message), ['i1', 'w1']);
    system
      ..buffer.capacity = 1000
      ..buffer.threshold = SpringLogLevel.trace
      ..console.threshold = SpringLogLevel.trace;
  });

  test('console and buffer can be switched off', () {
    runner
        .withPropertyValues([
          'logging.console.enabled=false',
          'logging.buffer.enabled=false',
        ])
        .run((context) => log.warning('nowhere'));
    expect(console, isEmpty);
    expect(system.buffer.isEmpty, isTrue);
    system
      ..consoleEnabled = true
      ..bufferEnabled = true;
  });

  test('logging.enabled=false leaves SpringLog alone', () {
    runner.withPropertyValues(['logging.enabled=false']).run((context) {
      expect(context, doesNotHaveBean<LoggingSystem>());
      expect(context, doesNotHaveBean<LoggingSystemInitializer>());
      expect(system.isInstalled, isFalse);
    });
  });

  test('bad configuration fails the start', () {
    runner
        .withPropertyValues(['logging.pattern.console=%m %thread'])
        .run((context) => expect(context, hasFailed()));
    runner
        .withPropertyValues(['logging.buffer.capacity=many'])
        .run((context) => expect(context, hasFailed()));
    runner
        .withPropertyValues(['logging.threshold.console=loud'])
        .run((context) => expect(context, hasFailed()));
    expect(system.isInstalled, isFalse);
  });

  test('custom appenders; a broken one does not stop the others', () {
    final collecting = CollectingAppender();
    final broken = BrokenAppender();
    system
      ..addAppender(broken)
      ..addAppender(collecting);
    addTearDown(() {
      system
        ..removeAppender(broken)
        ..removeAppender(collecting);
    });
    runner.run((context) => log.info('to all'));
    expect(collecting.messages, ['to all']);
    expect(console, ['INFO  [neon.shop] to all']);
    expect(system.removeAppender(collecting), isTrue);
    expect(system.removeAppender(collecting), isFalse);
  });

  test('runtime level changes (like /actuator/loggers)', () {
    runner.run((context) {
      final logging = context.getBean<LoggingSystem>();
      logging.setLevel('neon', SpringLogLevel.debug);
      expect(logging.levelOf('neon.shop'), SpringLogLevel.debug);
      expect(logging.loggerLevels, {'neon': SpringLogLevel.debug});
      log.debug('now visible');
      logging.rootLevel = SpringLogLevel.error;
      expect(logging.rootLevel, SpringLogLevel.error);
    });
    expect(console, ['DEBUG [neon.shop] now visible']);
  });

  test('without Boot: configure and install by hand', () {
    final environment = StandardEnvironment(systemEnvironment: const {})
      ..propertySources.addFirst(
        MapPropertySource('p', {'logging.level.root': 'debug'}),
      );
    SpringLog.level = SpringLogLevel.debug;
    system
      ..configure(environment)
      ..install()
      ..install(); // idempotent
    addTearDown(system.uninstall);
    log.debug('by hand');
    expect(SpringLog.level, SpringLogLevel.debug); // root configured: kept
    expect(console, ['DEBUG [neon.shop] by hand']);
  });
}
