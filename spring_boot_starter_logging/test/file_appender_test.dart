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
        maxFileSize: 30,
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

    test('maxHistory 0 keeps every archive, like Logback', () {
      final appender = FileAppender(
        '${dir.path}/k.log',
        pattern: LogPattern('%m'),
        maxFileSize: 30,
        maxHistory: 0,
      );
      for (var i = 1; i <= 10; i++) {
        appender.append(record('line-${'$i'.padLeft(4, '0')}'));
      }
      appender.close();
      expect(read('k.log'), 'line-0010\n');
      expect(read('k.log.1'), 'line-0007\nline-0008\nline-0009\n');
      expect(read('k.log.2'), 'line-0004\nline-0005\nline-0006\n');
      expect(read('k.log.3'), 'line-0001\nline-0002\nline-0003\n');
      expect(exists('k.log.4'), isFalse);
    });

    test('maxHistory 0 with totalSizeCap deletes only over the cap', () {
      final appender = FileAppender(
        '${dir.path}/z.log',
        pattern: LogPattern('%m'),
        maxFileSize: 30,
        maxHistory: 0,
        totalSizeCap: 60,
      );
      for (var i = 1; i <= 13; i++) {
        appender.append(record('line-${'$i'.padLeft(4, '0')}'));
      }
      appender.close();
      expect(read('z.log.1'), 'line-0010\nline-0011\nline-0012\n');
      expect(read('z.log.2'), 'line-0007\nline-0008\nline-0009\n');
      expect(exists('z.log.3'), isFalse);
    });

    test('cleanHistoryOnStart removes rolled-over files', () {
      for (final name in ['c.log', 'c.log.1', 'c.log.2']) {
        File('${dir.path}/$name').writeAsStringSync('old\n');
      }
      FileAppender('${dir.path}/c.log', cleanHistoryOnStart: true).close();
      expect(exists('c.log'), isTrue); // the current file is kept
      expect(exists('c.log.1') || exists('c.log.2'), isFalse);
    });

    test('totalSizeCap deletes the oldest archives', () {
      // 30-byte files of three 10-byte lines; archives may total 60 bytes.
      final appender = FileAppender(
        '${dir.path}/s.log',
        pattern: LogPattern('%m'),
        maxFileSize: 30,
        maxHistory: 5,
        totalSizeCap: 60,
      );
      for (var i = 1; i <= 13; i++) {
        appender.append(record('line-${'$i'.padLeft(4, '0')}'));
      }
      appender.close();
      expect(read('s.log'), 'line-0013\n');
      expect(read('s.log.1'), 'line-0010\nline-0011\nline-0012\n');
      expect(read('s.log.2'), 'line-0007\nline-0008\nline-0009\n');
      expect(exists('s.log.3'), isFalse); // within maxHistory, over the cap
    });

    test('maxFileSize 0 never rolls over; negative values are rejected', () {
      final appender = FileAppender('${dir.path}/n.log', maxFileSize: 0);
      for (var i = 0; i < 50; i++) {
        appender.append(record('x' * 100));
      }
      appender.close();
      expect(exists('n.log.1'), isFalse);
      expect(
        () => FileAppender('${dir.path}/x.log', maxHistory: -1),
        throwsArgumentError,
      );
      expect(
        () => FileAppender('${dir.path}/x.log', totalSizeCap: -1),
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

  group('logging.file.* and logging.logback.rollingpolicy.* properties', () {
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
            'logging.logback.rollingpolicy.max-file-size=1KB',
            'logging.logback.rollingpolicy.max-history=1',
            'logging.logback.rollingpolicy.total-size-cap=2KB',
          ])
          .run((context) {
            final file = LoggingSystem.instance.file!;
            expect(file.path, '${dir.path}/app/shop.log');
            expect(file.maxFileSize, 1024);
            expect(file.maxHistory, 1);
            expect(file.totalSizeCap, 2048);
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
            'logging.logback.rollingpolicy.max-file-size=big',
          ])
          .run((context) => expect(context, hasFailed()));
      runner
          .withPropertyValues([
            'logging.file.path=${dir.path}',
            'logging.logback.rollingpolicy.max-history=all',
          ])
          .run((context) => expect(context, hasFailed()));
    });

    test('the logging.file.* rolling names are gone: a warning, no effect', () {
      final warnings = <String>[];
      final stop = SpringLog.listen((record) {
        if (record.level == SpringLogLevel.warning) {
          warnings.add(record.message);
        }
      });
      addTearDown(stop);
      runner
          .withPropertyValues([
            'logging.file.path=${dir.path}',
            'logging.file.max-size=1KB',
            'logging.file.max-history=1',
            'logging.file.clean-history-on-start=true',
          ])
          .run((context) {
            final file = LoggingSystem.instance.file!;
            expect(file.maxFileSize, 10 * 1024 * 1024); // the defaults
            expect(file.maxHistory, 7);
            expect(file.totalSizeCap, 0);
          });
      expect(warnings, [
        // One element, split for the line width.
        // ignore: no_adjacent_strings_in_list
        'logging.file.max-size is not supported (ignored): use '
            'logging.logback.rollingpolicy.max-file-size',
        // One element, split for the line width.
        // ignore: no_adjacent_strings_in_list
        'logging.file.max-history is not supported (ignored): use '
            'logging.logback.rollingpolicy.max-history',
        // One element, split for the line width.
        // ignore: no_adjacent_strings_in_list
        'logging.file.clean-history-on-start is not supported (ignored): use '
            'logging.logback.rollingpolicy.clean-history-on-start',
      ]);
    });

    test("without logging.pattern.file: Spring Boot's file pattern", () {
      const ApplicationContextRunner()
          .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
          .withPropertyValues([
            'logging.console.enabled=false',
            'logging.file.name=${dir.path}/boot.log',
            'spring.application.name=shop',
          ])
          .run((context) => log.info('to the file'));
      expect(
        read('boot.log'),
        matches(
          RegExp(
            r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}(Z|[+-]\d\d:\d\d)  INFO '
            r'\d+ --- \[shop\] \[[^\]]+\] neon\.shop {32}: to the file\n$',
          ),
        ),
      );
    });
  });
}
