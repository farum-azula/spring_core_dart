@Tags(['supabase'])
library;

import 'package:spring_boot_starter_supabase/spring_auto_configuration.dart';
import 'package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

const _jwt = 'spring.security.oauth2.resourceserver.jwt';

void main() {
  ApplicationContextRunner runner(List<String> properties) =>
      const ApplicationContextRunner()
          .withAutoConfiguration(springBootAutoConfiguration)
          .withAutoConfiguration(
            springBootStarterSupabaseServerAutoConfiguration,
          )
          .withPropertyValues(properties);

  Map<String, String?> jwt(AssertableApplicationContext context) => {
    for (final key in [
      'jwk-set-uri',
      'secret-key',
      'issuer-uri',
      'jws-algorithms',
      'audiences',
      'required-claims.role',
      'authorities-claim-name',
      'authority-prefix',
    ])
      key: context.getBean<Environment>().getProperty('$_jwt.$key'),
  };

  test('a project with signing keys: its JWKS, asymmetric only', () {
    runner(['spring.supabase.url=$projectUrl']).run((context) {
      expect(context.startupFailure, isNull);
      expect(jwt(context), {
        'jwk-set-uri': '$projectUrl/auth/v1/.well-known/jwks.json',
        'secret-key': null,
        'issuer-uri': '$projectUrl/auth/v1',
        'jws-algorithms': 'ES256,RS256',
        'audiences': 'authenticated',
        'required-claims.role': 'authenticated',
        'authorities-claim-name': 'app_metadata.roles',
        'authority-prefix': 'ROLE_',
      });
    });
  });

  test('a project with a legacy secret: HS256 with it, no JWKS', () {
    runner([
      'spring.supabase.url=$projectUrl',
      'spring.supabase.auth.jwt-secret=0123456789abcdef0123456789abcdef',
    ]).run((context) {
      expect(context.startupFailure, isNull);
      expect(jwt(context), {
        'jwk-set-uri': null,
        'secret-key': '0123456789abcdef0123456789abcdef',
        'issuer-uri': '$projectUrl/auth/v1',
        'jws-algorithms': 'HS256',
        'audiences': 'authenticated',
        'required-claims.role': 'authenticated',
        'authorities-claim-name': 'app_metadata.roles',
        'authority-prefix': 'ROLE_',
      });
    });
  });

  test('the issuer of the configuration replaces <url>/auth/v1', () {
    runner([
      'spring.supabase.url=$projectUrl',
      'spring.supabase.auth.issuer=https://auth.example.com',
    ]).run((context) {
      expect(jwt(context)['issuer-uri'], 'https://auth.example.com');
    });
  });

  test("what the application sets itself wins over the starter's", () {
    runner([
      'spring.supabase.url=$projectUrl',
      '$_jwt.audiences=mine',
      '$_jwt.authority-prefix=SCOPE_',
    ]).run((context) {
      final values = jwt(context);
      expect(values['audiences'], 'mine');
      expect(values['authority-prefix'], 'SCOPE_');
      expect(values['required-claims.role'], 'authenticated');
    });
  });

  group('nothing is configured', () {
    for (final (name, properties) in [
      ('without a project', const <String>[]),
      (
        'with spring.supabase.auth.enabled=false',
        [
          'spring.supabase.url=$projectUrl',
          'spring.supabase.auth.enabled=false',
        ],
      ),
    ]) {
      test(name, () {
        runner(properties).run((context) {
          expect(context.startupFailure, isNull);
          expect(jwt(context).values, everyElement(isNull));
        });
      });
    }
  });

  group('the startup checks', () {
    test('an address with a trailing slash is refused', () {
      expect(
        () => SupabaseStartup(SupabaseProperties()..url = '$projectUrl/'),
        throwsStateError,
      );
      expect(
        () => SupabaseStartup(SupabaseProperties()..url = 'ftp://x'),
        throwsStateError,
      );
    });

    test('how the repositories reach the database, without the password', () {
      SupabaseStartup data(String? database, {bool asUser = false}) =>
          SupabaseStartup(
            SupabaseProperties()
              ..url = projectUrl
              ..db.url = database
              ..db.rls = asUser ? SupabaseRls.user : SupabaseRls.off,
          );
      expect(data(null).dataPath, 'the REST API of abcd.supabase.co');
      expect(
        data('postgresql://postgres:secret@db.abcd.supabase.co/postgres')
            .dataPath,
        'SQL over db.abcd.supabase.co:5432 (direct connection)',
      );
      const pooler = 'postgres.abcd:secret@aws-0-eu.pooler.supabase.com';
      expect(
        data('jdbc:postgresql://$pooler:5432/postgres', asUser: true).dataPath,
        'SQL over aws-0-eu.pooler.supabase.com:5432 (session pooler)',
      );
      final transaction = data('postgresql://$pooler:6543/postgres');
      expect(transaction.dataPath, contains('transaction pooler'));
      expect(transaction.warnings.single, contains('port 6543'));
      expect(transaction.warnings.single, isNot(contains('secret')));
      expect(
        () => data('postgresql://$pooler:6543/postgres', asUser: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('spring.supabase.db.rls'),
              isNot(contains('secret')),
            ),
          ),
        ),
      );
      expect(() => data('nonsense'), throwsStateError);
    });

    test('port 6543 is a transaction pooler on any address', () {
      // The dedicated pooler of a project, a self-hosted one: the host
      // does not have to say so.
      for (final host in ['db.abcd.supabase.co', 'pgbouncer.internal']) {
        final properties = SupabaseProperties()
          ..url = projectUrl
          ..db.url = 'postgresql://postgres:secret@$host:6543/postgres';
        final startup = SupabaseStartup(properties);
        expect(startup.dataPath, contains('transaction pooler'), reason: host);
        expect(startup.warnings.single, contains('port 6543'), reason: host);
        expect(
          () => SupabaseStartup(properties..db.rls = SupabaseRls.user),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(contains('transaction pooler'), isNot(contains('secret'))),
            ),
          ),
          reason: host,
        );
      }
    });

    test('rls: user needs the data source to be that database', () {
      const direct =
          'postgresql://postgres:secret@db.abcd.supabase.co/postgres';
      const pooler =
          'postgresql://postgres.abcd:secret@aws-0-eu.pooler.supabase.com:5432/postgres';
      SupabaseStartup start(String? dataSource, {bool asUser = true}) =>
          SupabaseStartup(
            SupabaseProperties()
              ..url = projectUrl
              ..db.url = direct
              ..db.rls = asUser ? SupabaseRls.user : SupabaseRls.off,
            dataSourceUrl: dataSource,
          );
      // The starter's default, the same address spelled out, none.
      expect(start(direct).dataPath, contains('direct connection'));
      expect(
        start('jdbc:postgresql://other:pw@db.abcd.supabase.co:5432/postgres')
            .dataPath,
        isNotNull,
      );
      expect(start(null).dataPath, isNotNull);
      // Another address of the same database: the hook would not run.
      expect(
        () => start(pooler),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('spring.datasource.url is another address'),
              contains('aws-0-eu.pooler.supabase.com:5432'),
              isNot(contains('secret')),
            ),
          ),
        ),
      );
      expect(() => start('nonsense://'), throwsStateError);
      // Without rls: user the application's data source is its business.
      expect(start(pooler, asUser: false).dataPath, isNotNull);
    });

    test('a client application is warned about what ships in it', () {
      final all = SupabaseProperties()
        ..url = projectUrl
        ..serviceRoleKey = 'service-key'
        ..db.url = 'postgresql://postgres:secret@db.abcd.supabase.co/postgres'
        ..auth.jwtSecret = 'secret';
      final client = SupabaseStartup(all, isClientApplication: true);
      expect(client.warnings, hasLength(3));
      expect(client.warnings.join('\n'), isNot(contains('secret@')));
      expect(client.warnings.join('\n'), isNot(contains('service-key')));
      expect(SupabaseStartup(all).warnings, isEmpty);
      expect(
        SupabaseStartup(
          SupabaseProperties()..url = projectUrl,
          isClientApplication: true,
        ).warnings,
        isEmpty,
      );
    });
  });
}
