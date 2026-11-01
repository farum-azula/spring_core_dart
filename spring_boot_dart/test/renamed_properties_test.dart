// The expected lines of the report are long keys that cannot be split.
// ignore_for_file: no_adjacent_strings_in_list

import 'dart:io';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:test/test.dart';

SpringApplication _app({
  List<String>? out,
  Map<String, String> dartDefines = const {},
}) => SpringApplication(
  [BeanModule('app', const [])],
  bannerMode: BannerMode.off,
  out: out?.add,
  dartDefines: dartDefines,
);

// The report of a start that failed, or null when it started.
String? _failure({
  List<String> args = const [],
  Map<String, String> environment = const {},
  Map<String, Object?> properties = const {},
  Map<String, String> dartDefines = const {},
}) {
  final out = <String>[];
  try {
    _app(
      out: out,
      dartDefines: dartDefines,
    ).run(args, systemEnvironment: environment, properties: properties).close();
  } on Object {
    return out.single;
  }
  return null;
}

void main() {
  group('the old name of a property stops the start', () {
    // Every renamed prefix, with a key below it and the key it is now.
    const cases = {
      'spring.cloud.openfeign.client.config.default.read-timeout':
          'spring.feign.client.config.default.read-timeout',
      'spring.jackson.default-property-inclusion':
          'spring.json.default-property-inclusion',
      'spring.servlet.multipart.max-file-size':
          'spring.web.multipart.max-file-size',
      'server.servlet.context-path': 'server.context-path',
      'server.servlet.session.cookie.same-site':
          'server.session.cookie.same-site',
      'logging.logback.rollingpolicy.max-file-size':
          'logging.file.rolling-policy.max-file-size',
      'spring.flyway.locations': 'spring.sql.migration.locations',
    };
    for (final MapEntry(key: old, value: current) in cases.entries) {
      test('$old is now $current', () {
        final report = _failure(properties: {old: 'x'});
        expect(report, contains('APPLICATION FAILED TO START'));
        expect(report, contains('  - $old is now $current'));
      });
    }

    test('the failure names the new key and says what to do', () {
      final report = _failure(properties: {'spring.jackson.time-zone': 'UTC'});
      expect(report, contains('These properties have been renamed:'));
      expect(
        report,
        contains('  - spring.jackson.time-zone is now spring.json.time-zone'),
      );
      expect(report, contains('Action:'));
      expect(report, contains('Rename it'));
    });

    test('several keys at once are all listed, sorted', () {
      final report = _failure(
        properties: {
          'spring.jackson.time-zone': 'UTC',
          'server.servlet.session.timeout': '15m',
          'spring.cloud.openfeign.oauth2.enabled': 'true',
          'logging.logback.rollingpolicy.max-history': '3',
          'spring.json.indent-output': 'true',
          'server.port': '0',
        },
      )!;
      expect(report, contains('Rename them'));
      final lines = report.split('\n').where((l) => l.startsWith('  - '));
      expect(lines, [
        '  - logging.logback.rollingpolicy.max-history is now '
            'logging.file.rolling-policy.max-history',
        '  - server.servlet.session.timeout is now server.session.timeout',
        '  - spring.cloud.openfeign.oauth2.enabled is now '
            'spring.feign.oauth2.enabled',
        '  - spring.jackson.time-zone is now spring.json.time-zone',
      ]);
    });

    test('a key of the command line is found', () {
      final report = _failure(args: ['--spring.jackson.time-zone=UTC']);
      expect(
        report,
        contains('  - spring.jackson.time-zone is now spring.json.time-zone'),
      );
    });

    test('a --dart-define is found', () {
      final report = _failure(
        dartDefines: {'server.servlet.context-path': '/shop'},
      );
      expect(
        report,
        contains(
          '  - server.servlet.context-path is now server.context-path',
        ),
      );
    });

    test('an environment variable is found in its relaxed form', () {
      final report = _failure(
        environment: {
          'SPRING_JACKSON_TIMEZONE': 'UTC',
          'SPRING_CLOUD_OPENFEIGN_CLIENT_CONFIG_DEFAULT_READTIMEOUT': '5s',
          'SPRING_SERVLET_MULTIPART_MAXFILESIZE': '5MB',
          'SERVER_SERVLET_SESSION_TIMEOUT': '15m',
          'LOGGING_LOGBACK_ROLLINGPOLICY_MAXHISTORY': '3',
          'SPRING_FLYWAY_LOCATIONS': 'x',
        },
      )!;
      final lines = report.split('\n').where((l) => l.startsWith('  - '));
      expect(lines, [
        '  - LOGGING_LOGBACK_ROLLINGPOLICY_MAXHISTORY is now '
            'LOGGING_FILE_ROLLINGPOLICY_MAXHISTORY',
        '  - SERVER_SERVLET_SESSION_TIMEOUT is now SERVER_SESSION_TIMEOUT',
        '  - SPRING_CLOUD_OPENFEIGN_CLIENT_CONFIG_DEFAULT_READTIMEOUT is now '
            'SPRING_FEIGN_CLIENT_CONFIG_DEFAULT_READTIMEOUT',
        '  - SPRING_FLYWAY_LOCATIONS is now SPRING_SQL_MIGRATION_LOCATIONS',
        '  - SPRING_JACKSON_TIMEZONE is now SPRING_JSON_TIMEZONE',
        '  - SPRING_SERVLET_MULTIPART_MAXFILESIZE is now '
            'SPRING_WEB_MULTIPART_MAXFILESIZE',
      ]);
    });

    test('a relaxed spelling of a key is found and named as it is '
        'written', () {
      final report = _failure(properties: {'spring.jackson.timeZone': 'UTC'});
      expect(
        report,
        contains('  - spring.jackson.timeZone is now spring.json.timeZone'),
      );
    });

    test('a key of a config file is found', () {
      final directory = Directory.systemTemp.createTempSync('renamed');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/application.properties')
        ..writeAsStringSync('server.servlet.session.timeout=15m\n');
      final report = _failure(
        args: ['--spring.config.import=file:${file.path}'],
      );
      expect(
        report,
        contains(
          '  - server.servlet.session.timeout is now '
          'server.session.timeout',
        ),
      );
    });

    test('the same key in two sources is listed once', () {
      final report = _failure(
        args: ['--spring.jackson.time-zone=UTC'],
        properties: {'spring.jackson.time-zone': 'UTC'},
      )!;
      expect(
        report.split('\n').where((l) => l.startsWith('  - ')),
        ['  - spring.jackson.time-zone is now spring.json.time-zone'],
      );
    });

    test('runAsync fails the same way', () async {
      final out = <String>[];
      await expectLater(
        _app(out: out).runAsync(
          const [],
          systemEnvironment: const {},
          properties: const {'server.servlet.context-path': '/shop'},
        ),
        throwsA(isA<RenamedPropertiesException>()),
      );
      expect(
        out.single,
        contains('  - server.servlet.context-path is now server.context-path'),
      );
    });

    test('the error carries the keys', () {
      expect(
        () => _app().run(
          const [],
          systemEnvironment: const {},
          properties: const {'spring.jackson.time-zone': 'UTC'},
        ),
        throwsA(
          isA<RenamedPropertiesException>().having(
            (e) => e.properties,
            'properties',
            {'spring.jackson.time-zone': 'spring.json.time-zone'},
          ),
        ),
      );
    });
  });

  group('the new names are not reported', () {
    test('the new keys start the application', () {
      expect(
        _failure(
          args: ['--spring.json.time-zone=UTC'],
          environment: const {
            'SPRING_JSON_TIMEZONE': 'UTC',
            'SPRING_FEIGN_CLIENT_DECODESLASH': 'true',
            'SERVER_SESSION_TIMEOUT': '15m',
            'LOGGING_FILE_ROLLINGPOLICY_MAXHISTORY': '3',
          },
          properties: const {
            'spring.feign.client.config.default.read-timeout': '5s',
            'spring.web.multipart.max-file-size': '5MB',
            'server.context-path': '/shop',
            'server.session.cookie.same-site': 'lax',
            'logging.file.rolling-policy.max-file-size': '10MB',
            'spring.sql.migration.locations': 'classpath:db/migration',
          },
        ),
        isNull,
      );
    });

    test('keys that only look like an old one start the application', () {
      expect(
        _failure(
          environment: const {
            'SPRING_JACKSONS_X': '1',
            'SERVER_SERVLETS': '1',
            'SPRING_CLOUD_CONFIG_URI': 'x',
          },
          properties: const {
            'spring.jacksonx.time-zone': 'UTC',
            'spring.jackson': 'a key without anything below it',
            'spring.cloud.config.uri': 'x',
            'spring.servlet.mvc.path': '/',
            'spring.web.servlet.name': 'x',
            'server.servlets.count': '1',
            'server.port': '0',
            'logging.logback.config': 'x',
            'logging.file.name': 'x.log',
            'logging.file.max-size': '10MB',
            'spring.flywaydb.url': 'x',
            'shop.spring.jackson.time-zone': 'UTC',
          },
        ),
        isNull,
      );
    });
  });

  test('every renamed prefix is a canonical name that differs from its '
      'replacement', () {
    for (final MapEntry(key: old, value: current)
        in RenamedPropertiesEnvironmentPostProcessor.renamed.entries) {
      expect(ConfigurationPropertyName.isValid(old), isTrue, reason: old);
      expect(ConfigurationPropertyName.isValid(current), isTrue);
      expect(old, isNot(current));
    }
  });
}
