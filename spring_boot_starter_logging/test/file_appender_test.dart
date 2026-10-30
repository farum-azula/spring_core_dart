@TestOn('vm')
library;

import 'dart:async';
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
  tearDown(() {
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['-R', 'u+w', dir.path]); // readOnly below
    }
    dir.deleteSync(recursive: true);
  });

  /// Makes [path] (a directory or a file) read-only; `false` where that
  /// does not stop this process from writing (Windows, root).
  bool readOnly(String path) {
    if (Platform.isWindows) {
      return false;
    }
    final isDirectory = FileSystemEntity.isDirectorySync(path);
    Process.runSync('chmod', [if (isDirectory) '555' else '444', path]);
    try {
      if (isDirectory) {
        File('$path/.probe').createSync();
      } else {
        File(path).openSync(mode: FileMode.append).closeSync();
      }
      return false; // still writable: root
    } on FileSystemException {
      return true;
    }
  }

  /// The records logged until the end of the test, at every level.
  List<SpringLogRecord> captureLogs() {
    final records = <SpringLogRecord>[];
    final previous = SpringLog.handler;
    final level = SpringLog.level;
    SpringLog.handler = records.add;
    SpringLog.level = SpringLogLevel.info;
    addTearDown(() {
      SpringLog.handler = previous;
      SpringLog.level = level;
    });
    return records;
  }

  List<String> messages(List<SpringLogRecord> records, SpringLogLevel level) =>
      [
        for (final record in records)
          if (record.level == level &&
              record.loggerName == 'spring_boot_starter_logging')
            record.message,
      ];

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

  // Logback reports an IO failure and goes on; an error escaping the
  // appender's microtask would end the application.
  group('a file that cannot be written', () {
    // 10-byte lines, 3 per file.
    String line(int i) => 'line-${'$i'.padLeft(4, '0')}';

    test(
      'a failed roll-over is reported once; lines go on in the file',
      () async {
        final logs = captureLogs();
        final path = '${dir.path}/logs/r.log';
        final appender = FileAppender(
          path,
          pattern: LogPattern('%m'),
          maxFileSize: 30,
        );
        for (var i = 1; i <= 3; i++) {
          appender.append(record(line(i)));
        }
        appender.flush();
        if (!readOnly('${dir.path}/logs')) {
          markTestSkipped('chmod does not restrict this process');
          return;
        }
        for (var i = 4; i <= 9; i++) {
          appender.append(record(line(i)));
          await pumpEventQueue(); // one flush per line: no uncaught error
        }
        expect(appender.isFailing, isFalse);
        appender.close();
        expect(
          File(path).readAsStringSync(),
          [for (var i = 1; i <= 9; i++) '${line(i)}\n'].join(),
        );
        expect(File('$path.1').existsSync(), isFalse);
        expect(messages(logs, SpringLogLevel.error), [
          startsWith('Cannot roll over the log file $path (it grows past'),
        ]);
      },
    );

    test('a file that cannot be opened again: lines dropped, reported once, '
        'written again later; close does not throw', () async {
      final logs = captureLogs();
      final path = '${dir.path}/logs/b.log';
      final appender = FileAppender(
        path,
        pattern: LogPattern('%m'),
        maxFileSize: 30,
      );
      for (var i = 1; i <= 3; i++) {
        appender.append(record(line(i)));
      }
      appender.flush();
      // The roll-over closes the file, cannot rename it nor open it again.
      if (!readOnly('${dir.path}/logs') || !readOnly(path)) {
        markTestSkipped('chmod does not restrict this process');
        return;
      }
      appender.append(record(line(4)));
      await pumpEventQueue();
      expect(appender.isFailing, isTrue);
      for (var i = 5; i <= 7; i++) {
        appender
          ..append(record(line(i)))
          ..flush();
      }
      expect(messages(logs, SpringLogLevel.error), [
        startsWith('Cannot roll over the log file $path'),
        startsWith('Cannot write the log file $path (its lines are dropped'),
      ]);

      Process.runSync('chmod', ['644', path]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      appender.append(record(line(8)));
      await pumpEventQueue();
      expect(appender.isFailing, isFalse);
      expect(messages(logs, SpringLogLevel.info), [
        'The log file $path is written again; lines lost meanwhile: 4',
      ]);
      appender.close();
      expect(
        File(path).readAsStringSync(),
        endsWith('${line(3)}\n${line(8)}\n'),
      );

      // Broken again, then closed: no error.
      final broken = FileAppender(
        '${dir.path}/c.log',
        pattern: LogPattern('%m'),
        maxFileSize: 30,
      );
      for (var i = 1; i <= 3; i++) {
        broken.append(record(line(i)));
      }
      broken.flush();
      readOnly(dir.path);
      readOnly('${dir.path}/c.log');
      broken
        ..append(record(line(4)))
        ..flush();
      expect(broken.isFailing, isTrue);
      expect(broken.close, returnsNormally);
      expect(broken.close, returnsNormally);
    });

    // On a full disk the file opens and the next write fails: opening it
    // again is no recovery. Reporting it as one flooded the console with
    // "Cannot write" / "written again" pairs every 20 ms.
    test('a full disk: reported once until a write works, the pause keeps '
        'growing; a later failure is reported again', () async {
      final logs = captureLogs();
      final disk = _Disk();
      final path = '${dir.path}/full.log';
      await disk.run(() async {
        final appender =
            FileAppender(path, pattern: LogPattern('%m'), maxFileSize: 0)
              ..append(record(line(1)))
              ..flush();
        disk.full = true;
        appender
          ..append(record(line(2)))
          ..flush();
        expect(appender.isFailing, isTrue);

        // After the first pause (20 ms) the file opens, the write fails.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final opens = disk.opens;
        appender
          ..append(record(line(3)))
          ..flush();
        expect(disk.opens, opens + 1);
        expect(appender.isFailing, isTrue);
        // The pause is 80 ms now, not 20 ms again.
        final waited = Stopwatch()..start();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        appender
          ..append(record(line(4)))
          ..flush();
        if (waited.elapsedMilliseconds < 80) {
          expect(disk.opens, opens + 1, reason: 'line 4 is dropped unwritten');
        }
        const reason = 'writeFrom failed (No space left on device)';
        expect(messages(logs, SpringLogLevel.error), [
          startsWith('Cannot write the log file $path (its lines are dropped'),
        ]);
        expect(messages(logs, SpringLogLevel.error).single, endsWith(reason));
        expect(messages(logs, SpringLogLevel.info), isEmpty);

        disk.full = false;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        appender
          ..append(record(line(5)))
          ..flush();
        expect(appender.isFailing, isFalse);
        expect(messages(logs, SpringLogLevel.info), [
          'The log file $path is written again; lines lost meanwhile: 3',
        ]);

        // A new failure is reported again; the pause starts at 20 ms.
        disk.full = true;
        appender
          ..append(record(line(6)))
          ..flush();
        expect(messages(logs, SpringLogLevel.error), hasLength(2));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final again = disk.opens;
        appender
          ..append(record(line(7)))
          ..flush();
        expect(disk.opens, again + 1);
        expect(messages(logs, SpringLogLevel.error), hasLength(2));
        appender.close();
      });
      expect(File(path).readAsStringSync(), '${line(1)}\n${line(5)}\n');
    });

    test(
      'LoggingSystem: removeAppender of a broken appender does not throw',
      () {
        captureLogs();
        final system = LoggingSystem.instance;
        final throwing = _ThrowingAppender();
        system.addAppender(throwing);
        expect(system.removeAppender(throwing), isTrue);
        expect(system.appenders, isNot(contains(throwing)));
      },
    );
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

    test('a file that cannot be opened is reported; the start goes on, '
        'like Logback', () {
      final logs = captureLogs();
      Directory('${dir.path}/ro').createSync();
      if (!readOnly('${dir.path}/ro')) {
        markTestSkipped('chmod does not restrict this process');
        return;
      }
      for (final property in [
        'logging.file.name=${dir.path}/ro/app.log',
        'logging.file.path=${dir.path}/ro/logs',
      ]) {
        logs.clear();
        runner.withPropertyValues([property]).run((context) {
          expect(context, isNot(hasFailed()));
          expect(LoggingSystem.instance.file, isNull);
          log.info('still logged');
        });
        expect(messages(logs, SpringLogLevel.error), [
          startsWith('Cannot open the log file ${dir.path}/ro/'),
        ]);
      }
    });

    test('a file broken while running: the close does not throw and gives '
        'the handler back', () {
      captureLogs();
      final handler = SpringLog.handler;
      Directory('${dir.path}/run').createSync();
      runner
          .withPropertyValues([
            'logging.file.name=${dir.path}/run/app.log',
            'logging.logback.rollingpolicy.max-file-size=30B',
          ])
          .run((context) {
            log.info('first line, long enough');
            LoggingSystem.instance.file!.flush();
            if (!readOnly('${dir.path}/run') ||
                !readOnly('${dir.path}/run/app.log')) {
              return;
            }
            log.info('a line that rolls over');
            LoggingSystem.instance.file!.flush();
            expect(LoggingSystem.instance.file!.isFailing, isTrue);
          });
      expect(SpringLog.handler, same(handler));
      expect(LoggingSystem.instance.isInstalled, isFalse);
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

final class _ThrowingAppender extends LogAppender {
  @override
  void write(SpringLogRecord record) {}

  @override
  void close() => throw StateError('broken');
}

/// A disk that fills up: the files are real, but while [full] is set every
/// write fails with "No space left on device" while opening a file still
/// works, as on a real full disk. Counts the files opened.
final class _Disk {
  bool full = false;
  int opens = 0;

  /// Runs [body] with every `File(...)` it creates on this disk.
  R run<R>(R Function() body) => IOOverrides.runZoned(
    body,
    // The real File is made outside the overrides.
    createFile: (path) => _DiskFile(this, Zone.root.run(() => File(path))),
  );
}

final class _DiskFile implements File {
  _DiskFile(this._disk, this._file);

  final _Disk _disk;
  final File _file;

  @override
  String get path => _file.path;

  @override
  Directory get parent => _file.parent;

  @override
  bool existsSync() => _file.existsSync();

  @override
  int lengthSync() => _file.lengthSync();

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) {
    _disk.opens++;
    return _DiskRandomAccessFile(_disk, _file.openSync(mode: mode));
  }

  // FileAppender uses nothing else of File.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DiskRandomAccessFile implements RandomAccessFile {
  _DiskRandomAccessFile(this._disk, this._file);

  final _Disk _disk;
  final RandomAccessFile _file;

  @override
  String get path => _file.path;

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    if (_disk.full) {
      throw FileSystemException(
        'writeFrom failed',
        path,
        const OSError('No space left on device', 28),
      );
    }
    _file.writeFromSync(buffer, start, end);
  }

  @override
  void closeSync() => _file.closeSync();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
