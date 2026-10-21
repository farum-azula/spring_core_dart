@TestOn('vm')
library;

import 'dart:io';

import 'package:spring_boot_starter_logging/spring_auto_configuration.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

SpringLogRecord record(String message, [SpringLogLevel? level]) =>
    SpringLogRecord(level ?? SpringLogLevel.info, 'neon.shop', message);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('spring_log_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String read(String name) => File('${dir.path}/$name').readAsStringSync();
  bool exists(String name) => File('${dir.path}/$name').existsSync();

  group('FileAppender', () {
    test('writes a burst at once, appends, creates directories', () async {
      final path = '${dir.path}/nested/logs/app.log';
      final appender = FileAppender(path, pattern: LogPattern('%p %m'))
        ..append(record('one'))
        ..append(record('two'));
      expect(File(path).readAsStringSync(), isEmpty); // not yet: one write
      await pumpEventQueue();
      expect(File(path).readAsStringSync(), 'INFO one\nINFO two\n');

      appender
        ..append(record('three'))
        ..flush();
      expect(File(path).readAsStringSync(), endsWith('INFO three\n'));
      appender
        ..append(record('four'))
        ..close() // writes the rest
        ..append(record('ignored'));
      expect(File(path).readAsStringSync().split('\n'), hasLength(5));

      // Reopening appends.
      FileAppender(path, pattern: LogPattern('%m'))
        ..append(record('five'))
        ..close();
      expect(File(path).readAsStringSync(), endsWith('four\nfive\n'));
    });

    test('threshold', () {
      FileAppender(
          '${dir.path}/t.log',
          pattern: LogPattern('%m'),
          threshold: SpringLogLevel.warning,
        )
        ..append(record('no'))
        ..append(record('yes', SpringLogLevel.error))
        ..close();
      expect(read('t.log'), 'yes\n');
    });

    test('rolls over by size and keeps maxHistory files', () {
      // Each line is 10 bytes ("line-0001\n"): 3 lines per 30-byte file.
      final appender = FileAppender(
        '${dir.path}/r.log',
        pattern: LogPattern('%m'),
        maxSize: 30,
        maxHistory: 2,
      );
      for (var i = 1; i <= 10; i++) {
        appender.append(record('line-${'$i'.padLeft(4, '0')}'));
      }
      appender.close();
      expect(read('r.log'), 'line-0010\n');
      expect(read('r.log.1'), 'line-0007\nline-0008\nline-0009\n');
      expect(read('r.log.2'), 'line-0004\nline-0005\nline-0006\n');
      expect(exists('r.log.3'), isFalse); // line-0001..3 dropped
    });

    test('cleanHistoryOnStart removes rolled-over files', () {
      for (final name in ['c.log', 'c.log.1', 'c.log.2']) {
        File('${dir.path}/$name').writeAsStringSync('old\n');
      }
      FileAppender('${dir.path}/c.log', cleanHistoryOnStart: true).close();
      expect(exists('c.log'), isTrue); // the current file is kept
      expect(exists('c.log.1') || exists('c.log.2'), isFalse);
    });

    test('maxSize 0 never rolls over; negative values are rejected', () {
      final appender = FileAppender('${dir.path}/n.log', maxSize: 0);
      for (var i = 0; i < 50; i++) {
        appender.append(record('x' * 100));
      }
      appender.close();
      expect(exists('n.log.1'), isFalse);
      expect(
        () => FileAppender('${dir.path}/x.log', maxHistory: -1),
        throwsArgumentError,
      );
      expect(FileAppender.isSupported, isTrue);
    });
  });

  test('parseDataSize', () {
    expect(parseDataSize('10MB'), 10 * 1024 * 1024);
    expect(parseDataSize(' 512 kb '), 512 * 1024);
    expect(parseDataSize('1GB'), 1024 * 1024 * 1024);
    expect(parseDataSize('100B'), 100);
    expect(parseDataSize('2048'), 2048);
    expect(() => parseDataSize('ten'), throwsFormatException);
    expect(() => parseDataSize('1.5MB'), throwsFormatException);
  });

  group('logging.file.* properties', () {
    final runner = const ApplicationContextRunner()
        .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
        .withPropertyValues([
          'logging.console.enabled=false',
          'logging.pattern.file=%p [%logger] %m',
        ]);
    const log = SpringLog('neon.shop');
    late SpringLogLevel savedLevel;
    setUp(() => savedLevel = SpringLog.level);
    tearDown(() {
      SpringLog.level = savedLevel;
      LoggingSystem.instance
        ..consoleEnabled = true
        ..fileDirectory = null;
    });

    test('logging.file.path writes spring.log; closed with the context', () {
      runner.withPropertyValues(['logging.file.path=${dir.path}/logs/']).run((
        context,
      ) {
        expect(
          LoggingSystem.instance.file?.path,
          '${dir.path}/logs/spring.log',
        );
        log
          ..info('to the file')
          ..debug('below root level');
      });
      expect(read('logs/spring.log'), 'INFO [neon.shop] to the file\n');
      expect(LoggingSystem.instance.file, isNull);
    });

    test('logging.file.name wins; relative to fileDirectory', () {
      LoggingSystem.instance.fileDirectory = dir.path;
      runner
          .withPropertyValues([
            'logging.file.name=app/shop.log',
            'logging.file.path=ignored',
            'logging.threshold.file=warn',
            'logging.file.max-size=1KB',
            'logging.file.max-history=1',
          ])
          .run((context) {
            final file = LoggingSystem.instance.file!;
            expect(file.path, '${dir.path}/app/shop.log');
            expect(file.maxSize, 1024);
            expect(file.maxHistory, 1);
            log
              ..info('console only')
              ..warning('kept');
          });
      expect(read('app/shop.log'), 'WARN [neon.shop] kept\n');
      expect(exists('ignored/spring.log'), isFalse);
    });

    test('absolute locations ignore fileDirectory', () {
      LoggingSystem.instance.fileDirectory = '/somewhere/else/';
      runner
          .withPropertyValues(['logging.file.name=${dir.path}/abs.log'])
          .run((context) => log.info('absolute'));
      expect(read('abs.log'), 'INFO [neon.shop] absolute\n');
      LoggingSystem.instance.fileDirectory = '${dir.path}/';
      runner
          .withPropertyValues(['logging.file.path=rel'])
          .run(
            (context) => expect(
              LoggingSystem.instance.file?.path,
              '${dir.path}/rel/spring.log',
            ),
          );
    });

    test('no file properties: no file; bad values fail the start', () {
      runner.run((context) => expect(LoggingSystem.instance.file, isNull));
      runner
          .withPropertyValues([
            'logging.file.path=${dir.path}',
            'logging.file.max-size=big',
          ])
          .run((context) => expect(context, hasFailed()));
      runner
          .withPropertyValues([
            'logging.file.path=${dir.path}',
            'logging.file.max-history=all',
          ])
          .run((context) => expect(context, hasFailed()));
    });
  });
}
