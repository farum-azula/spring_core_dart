@TestOn('vm')
library;

import 'dart:io';

import 'package:spring_boot_starter_logging/spring_auto_configuration.dart';
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

const log = SpringLog('neon.shop');

SpringLogRecord record(
  String message, {
  SpringLogLevel level = SpringLogLevel.info,
  Map<String, Object?> fields = const {},
}) => SpringLogRecord(level, 'neon.shop', message, fields: fields);

String format(
  String pattern,
  SpringLogRecord record, [
  Map<String, String>? v,
]) => LogPattern(pattern, variables: v ?? const {}).formatLine(record);

final class Announcer implements EnvironmentPostProcessor {
  @override
  void postProcessEnvironment(
    ConfigurableEnvironment environment,
    SpringApplication application,
  ) => const SpringLog('neon.early').warning('before the logging system');
}

void main() {
  group('Logback conversions', () {
    test('colour words are always ANSI, like Logback', () {
      expect(format('%red(%m)', record('x')), '\x1B[31mx\x1B[0;39m');
      expect(format('%boldGreen(%m)', record('x')), '\x1B[1;32mx\x1B[0;39m');
      expect(format('%gray(%m)', record('x')), '\x1B[1;30mx\x1B[0;39m');
      String highlight(SpringLogLevel level) =>
          format('%highlight(%p)', record('x', level: level));
      expect(highlight(SpringLogLevel.error), '\x1B[1;31mERROR\x1B[0;39m');
      expect(highlight(SpringLogLevel.warning), '\x1B[31mWARN\x1B[0;39m');
      expect(highlight(SpringLogLevel.info), '\x1B[34mINFO\x1B[0;39m');
      expect(highlight(SpringLogLevel.debug), '\x1B[39mDEBUG\x1B[0;39m');
      expect(() => LogPattern('%red'), throwsFormatException);
    });

    test('%replace with a regex and Java group references', () {
      expect(format(r"%replace(%m){'\s+', '_'}", record('a  b c')), 'a_b_c');
      expect(
        format(r"%replace(%m){'(\d+)-(\d+)', '$2-$1'}", record('id 12-34')),
        'id 34-12',
      );
      expect(format("%replace(%m){'x', ''}", record('xax')), 'a');
      expect(() => LogPattern('%replace(%m){x}'), throwsFormatException);
    });

    test('%kvp writes the fields as key-value pairs', () {
      final fields = record('m', fields: {'order': 7, 'user': 'ada'});
      expect(format('%kvp', fields), 'order="7" user="ada"');
      expect(format('%kvp{SINGLE}', fields), "order='7' user='ada'");
      expect(format('%kvp{NONE}', fields), 'order=7 user=ada');
      expect(format('[%kvp]', record('m')), '[]');
    });

    test('%prefix names each conversion', () {
      final fields = record('paid', fields: {'order': 7});
      expect(
        format('%prefix(%p %logger %X{order}) %m', fields),
        'level=INFO logger=neon.shop order=7 paid',
      );
    });

    test('%property reads variables, null when missing', () {
      expect(
        format('%property{LOG_FILE}|%property{nope}', record('x'), {
          'LOG_FILE': 'shop.log',
        }),
        'shop.log|null',
      );
      expect(format('%property', record('x')), 'Property_HAS_NO_KEY');
    });
  });

  group('logging properties', () {
    final system = LoggingSystem.instance;
    final console = <String>[];
    late Directory dir;
    late SpringLogLevel savedLevel;
    final runner = const ApplicationContextRunner()
        .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
        .withPropertyValues(['logging.pattern.console=%p %m']);

    setUp(() {
      savedLevel = SpringLog.level;
      console.clear();
      system
        ..console.out = console.add
        ..buffer.clear();
      dir = Directory.systemTemp.createTempSync('spring_logback_');
    });
    tearDown(() {
      SpringLog.level = savedLevel;
      dir.deleteSync(recursive: true);
    });

    test('on/off properties in any case; invalid ones fail', () {
      runner
          .withPropertyValues([
            'logging.console.enabled=FALSE',
            'logging.buffer.enabled=Off',
          ])
          .run((context) {
            expect(context.hasFailed, isFalse);
            log.info('x');
            expect(system.consoleEnabled, isFalse);
            expect(system.bufferEnabled, isFalse);
          });
      expect(console, isEmpty);
      expect(system.buffer.records, isEmpty);
      for (final key in [
        'logging.console.enabled',
        'logging.buffer.enabled',
        'logging.include-application-name',
        'logging.enabled',
      ]) {
        runner.withPropertyValues(['$key=nope']).run((context) {
          expect(context, hasFailed(), reason: key);
          expect('${context.startupFailure}', contains(key));
        });
      }
      runner.withPropertyValues(['logging.enabled=FALSE']).run((context) {
        expect(context, doesNotHaveBean<LoggingSystem>());
      });
    });

    test('an empty console pattern turns the console off', () {
      runner.withPropertyValues(['logging.pattern.console=']).run((context) {
        log.info('x');
        expect(system.consoleEnabled, isFalse);
      });
      expect(console, isEmpty);
      expect(system.buffer.records.single.message, 'x');
    });

    test('a threshold or level of false (YAML off) is OFF', () {
      runner
          .withPropertyValues(['logging.threshold.console=false'])
          .run((context) => log.error('x'));
      expect(console, isEmpty);
      final environment = StandardEnvironment(systemEnvironment: const {})
        ..propertySources.addFirst(
          const MapPropertySource('yaml', {
            'logging.level.root': false,
            'logging.level.neon': 'FALSE',
          }),
        );
      SpringApplication.applyLoggingLevels(environment);
      expect(SpringLog.level, SpringLogLevel.off);
      expect(SpringLog.configuredLevels, {'neon': SpringLogLevel.off});
      SpringLog.resetLevels();
    });

    test('logging.charset.file; file-name-pattern is ignored with a '
        'warning', () {
      final warnings = <String>[];
      addTearDown(SpringLog.listen((r) => warnings.add(r.message)));
      runner
          .withPropertyValues([
            'logging.file.name=${dir.path}/shop.log',
            'logging.pattern.file=%m',
            'logging.charset.file=ISO-8859-1',
            'logging.logback.rollingpolicy.file-name-pattern=x-%i.gz',
          ])
          .run((context) {
            expect(context.hasFailed, isFalse);
            log.info('café ☕');
          });
      expect(File('${dir.path}/shop.log').readAsBytesSync(), [
        ...'caf'.codeUnits,
        0xe9,
        0x20,
        0x3f,
        0x0a,
      ]);
      expect(
        warnings,
        contains(startsWith('logging.logback.rollingpolicy.file-name-pattern')),
      );
      // Java's aliases (Charset.forName) work too.
      for (final (name, charset) in [
        ('utf8', 'UTF8'),
        ('latin', 'ISO8859_1'),
        ('ascii', 'ascii7'),
      ]) {
        runner
            .withPropertyValues([
              'logging.file.name=${dir.path}/$name.log',
              'logging.pattern.file=%m',
              'logging.charset.file=$charset',
            ])
            .run((context) {
              expect(context.hasFailed, isFalse, reason: charset);
              log.info('é');
            });
      }
      expect(File('${dir.path}/utf8.log').readAsBytesSync(), [
        0xc3,
        0xa9,
        0x0a,
      ]);
      expect(File('${dir.path}/latin.log').readAsBytesSync(), [0xe9, 0x0a]);
      expect(File('${dir.path}/ascii.log').readAsBytesSync(), [0x3f, 0x0a]);
      runner
          .withPropertyValues([
            'logging.file.name=${dir.path}/other.log',
            'logging.charset.file=klingon',
          ])
          .run((context) {
            expect(context, hasFailed());
            expect(
              '${context.startupFailure}',
              contains('logging.charset.file'),
            );
          });
    });

    test('an empty file pattern writes no file', () {
      runner
          .withPropertyValues([
            'logging.file.name=${dir.path}/none.log',
            'logging.pattern.file=',
          ])
          .run((context) {
            expect(system.file, isNull);
          });
      expect(File('${dir.path}/none.log').existsSync(), isFalse);
    });

    test('lines logged before the logging system are replayed into its '
        'file and buffer, not the console', () {
      final printed = <SpringLogRecord>[];
      final previous = SpringLog.handler;
      SpringLog.handler = printed.add;
      addTearDown(() => SpringLog.handler = previous);
      SpringApplication(
        const [],
        autoConfigurations: [springBootStarterLoggingAutoConfiguration],
        environmentPostProcessors: [Announcer()],
        bannerMode: BannerMode.off,
      ).run([
        '--logging.file.name=${dir.path}/app.log',
        '--logging.pattern.file=%p %logger %m',
        '--logging.pattern.console=%p %m',
        '--spring.main.log-startup-info=false',
      ], systemEnvironment: const {}).close();
      expect(
        File('${dir.path}/app.log').readAsLinesSync(),
        contains('WARN neon.early before the logging system'),
      );
      expect(
        system.buffer.records.map((r) => r.message),
        contains('before the logging system'),
      );
      // Shown once, by the handler of the time.
      expect(
        printed.map((r) => r.message),
        contains('before the logging system'),
      );
      expect(console, isNot(contains('WARN before the logging system')));
    });
  });
}
