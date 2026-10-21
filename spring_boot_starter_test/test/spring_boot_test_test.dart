import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('springBootTest', () {
    final app = springBootTest(
      SpringApplication([appModule()]),
      args: ['--greeting.prefix=from-args'],
      properties: {'greeting.prefix': 'Hey', 'app.mode': 'test'},
      profiles: ['test', 'fast'],
      overrides: [BeanOverride<Mailer>(FakeMailer(), name: 'smtpMailer')],
    );

    test('starts the application with test properties and profiles', () {
      expect(app.getBean<Greeter>().greet('Ada'), 'Hey, Ada');
      expect(app.environment.activeProfiles, ['test', 'fast']);
      expect(app.environment.getProperty('app.mode'), 'test');
      expect(app.args, ['--greeting.prefix=from-args']);
      expect(app.output.single, startsWith('Started application in '));
      expect(app, hasSingleBean<Greeter>());
    });

    test('an override keeps the name and qualifiers of the bean', () {
      expect(app.getBeanByName('smtpMailer'), isA<FakeMailer>());
      expect(app.getBean<Mailer>(qualifier: 'primaryMail'), isA<FakeMailer>());
      expect(app.getBean<Notifier>().notify('Ada'), 'fake: Hey, Ada');
      expect(app.getBeanByName('sesMailer'), isA<SesMailer>());
    });

    var first = 0;
    test('markDirty gives the next test a fresh context', () {
      app.getBean<Counter>().value = 5;
      first = identityHashCode(app.context);
      app.markDirty();
    });

    test('(fresh context)', () {
      expect(identityHashCode(app.context), isNot(first));
      expect(app.getBean<Counter>().value, 0);
    });

    test('the context is shared between tests otherwise', () {
      final counter = app.getBean<Counter>()..value = 7;
      expect(app.getBean<Counter>(), same(counter));
    });
  });

  group('overriding the only bean of a type', () {
    final app = springBootTest(
      SpringApplication([appModule()]),
      overrides: [BeanOverride<Greeter>(FakeGreeter())],
    );

    test('the real bean is never created', () {
      RealGreeter.created = 0;
      expect(app.getBean<Notifier>().notify('Bob'), 'smtp: fake Bob');
      expect(app.getBean<Greeter>(), isA<FakeGreeter>());
      expect(app.getBeanByName('greeter'), isA<FakeGreeter>());
      expect(RealGreeter.created, 0);
    });
  });

  group('the context is unavailable outside tests', () {
    final app = springBootTest(SpringApplication([appModule()]));
    final error = () {
      try {
        app.context;
      } on StateError catch (error) {
        return error;
      }
      return null;
    }();

    test('a helpful error before setUpAll', () {
      expect(error?.message, contains('not started'));
    });
  });

  group('SpringLog state is restored', () {
    late SpringLogLevel before;
    setUpAll(() => before = SpringLog.level);
    group('inner', () {
      final app = springBootTest(
        SpringApplication([appModule()]),
        properties: {
          'logging.level.root': 'trace',
          'logging.level.test.app': 'error',
        },
      );
      test('levels from properties apply during the tests', () {
        expect(app, hasBean<Counter>());
        expect(SpringLog.level, SpringLogLevel.trace);
        expect(SpringLog.levelOf('test.app'), SpringLogLevel.error);
      });
    });
    test('and are restored afterwards', () {
      expect(SpringLog.level, before);
      expect(SpringLog.configuredLevels, isEmpty);
    });
  });

  group('test/resources: the test classpath', () {
    group('inner', () {
      final app = springBootTest(
        SpringApplication([appModule()]),
        profiles: ['test'],
        propertyFiles: ['classpath:extra-test.properties'],
        properties: {'app.extra': 'from properties'},
      );

      test('application-test.properties is found by its profile', () {
        expect(app.getBean<Greeter>().greet('Ada'), 'From the test file, Ada');
        // Resolved against this package, wherever `dart test` runs from.
        expect(app.resourceDirectories, [
          allOf(
            startsWith('/'),
            endsWith('spring_boot_starter_test/test/resources'),
          ),
        ]);
        expect(ClasspathResources.directories, app.resourceDirectories);
      });

      test('propertyFiles win over config files, properties over both', () {
        expect(
          app.environment.getProperty('app.source'),
          'extra-test.properties',
        );
        expect(app.environment.getProperty('app.extra'), 'from properties');
      });

      test('test data is a classpath resource', () {
        expect(
          app.context
              .getResource('classpath:data/books.txt')
              .readAsStringSync(),
          'Dune;Solaris\n',
        );
      });
    });

    group('own directories', () {
      final app = springBootTest(
        SpringApplication([appModule()]),
        profiles: ['other'],
        resourceDirectories: ['test/other_resources', 'test/resources'],
      );

      test('the first listed directory comes first', () {
        expect(ClasspathResources.directories, [
          endsWith('/test/other_resources'),
          endsWith('/test/resources'),
        ]);
        expect(app.environment.getProperty('other'), 'yes');
      });
    });

    test('directories are removed after the tests', () {
      expect(ClasspathResources.directories, isEmpty);
    });
  });
}
