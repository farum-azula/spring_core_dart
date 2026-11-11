// A data source that is set up wrongly stops the application with a message
// that names the property and says what to do.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/fake_jdbc.dart';

// A second driver for the scheme the fake one handles.
class _TwinDriver extends FakeJdbcDriver {
  @override
  String get name => 'twin';
}

Environment _environment(Map<String, String> settings) =>
    StandardEnvironment(systemEnvironment: {})
      ..propertySources.addFirst(MapPropertySource('test', settings));

DataSourceProperties _properties(Map<String, String> settings) =>
    DataSourceProperties.fromEnvironment(_environment(settings));

Matcher _failure({
  required String property,
  required String message,
  String? action,
}) => isA<DataSourceConfigurationException>()
    .having((e) => e.property, 'property', property)
    .having((e) => e.message, 'message', contains(message))
    .having((e) => e.action, 'action', contains(action ?? property));

void main() {
  group('the settings', () {
    test('without a URL name the property and what to set', () {
      expect(
        () => _properties({'spring.datasource.username': 'ada'}),
        throwsA(
          _failure(
            property: 'spring.datasource.url',
            message: 'has no URL',
            action: 'sqlite:file:app.db',
          ),
        ),
      );
    });

    test('a named data source says its own prefix', () {
      expect(
        () => DataSourceProperties.fromEnvironment(
          _environment({'spring.datasources.reports.username': 'ada'}),
          prefix: DataSourceProperties.prefixOf('reports'),
          name: 'reports',
        ),
        throwsA(
          _failure(
            property: 'spring.datasources.reports.url',
            message: 'The data source reports has no URL',
          ),
        ),
      );
    });

    test('a URL without a scheme', () {
      expect(
        () => _properties({'spring.datasource.url': 'app.db'}),
        throwsA(
          _failure(
            property: 'spring.datasource.url',
            message: 'has no scheme',
            action: 'sqlite:file:app.db',
          ),
        ),
      );
    });

    test('a URL that is not one', () {
      expect(
        () => _properties({'spring.datasource.url': 'sqlite://[bad'}),
        throwsA(
          _failure(
            property: 'spring.datasource.url',
            message: 'is not a URL',
            action: 'postgresql://host:5432/database',
          ),
        ),
      );
    });

    test('a jdbc: prefix is accepted', () {
      final properties = _properties({
        'spring.datasource.url': 'jdbc:sqlite:file:app.db',
      });
      expect(properties.url.scheme, 'sqlite');
    });

    test('a pool without a connection', () {
      expect(
        () => _properties({
          'spring.datasource.url': 'sqlite:file:a.db',
          'spring.datasource.pool.max-size': '0',
        }),
        throwsA(
          _failure(
            property: 'spring.datasource.pool.max-size',
            message: 'at least 1',
          ),
        ),
      );
    });

    test('more idle connections than the pool holds', () {
      expect(
        () => _properties({
          'spring.datasource.url': 'sqlite:file:a.db',
          'spring.datasource.pool.max-size': '2',
          'spring.datasource.pool.min-idle': '3',
        }),
        throwsA(
          _failure(
            property: 'spring.datasource.pool.min-idle',
            message: 'between 0 and pool.max-size (2)',
          ),
        ),
      );
    });

    test('a negative timeout shows the value that was written', () {
      expect(
        () => _properties({
          'spring.datasource.url': 'sqlite:file:a.db',
          'spring.datasource.pool.idle-timeout': '-5s',
        }),
        throwsA(
          _failure(
            property: 'spring.datasource.pool.idle-timeout',
            message: '"-5s"',
          ),
        ),
      );
    });

    test('a duration that is not one is explained', () {
      expect(
        () => _properties({
          'spring.datasource.url': 'sqlite:file:a.db',
          'spring.datasource.pool.connection-timeout': 'soon',
        }),
        throwsA(
          _failure(
            property: 'spring.datasource.pool.connection-timeout',
            message: 'a duration such as 500ms, 30s or 10m',
          ),
        ),
      );
    });
  });

  group('choosing the driver', () {
    final fake = FakeJdbcDriver();

    test('by the scheme of the URL', () {
      final properties = _properties({'spring.datasource.url': 'fake:x'});
      expect(properties.selectDriver([fake]), same(fake));
    });

    test('by name, which wins over the scheme', () {
      final twin = _TwinDriver();
      final properties = _properties({
        'spring.datasource.url': 'fake:x',
        'spring.datasource.driver': 'twin',
      });
      expect(properties.selectDriver([fake, twin]), same(twin));
    });

    test('a name no driver has lists the drivers there are', () {
      final properties = _properties({
        'spring.datasource.url': 'fake:x',
        'spring.datasource.driver': 'oracle',
      });
      expect(
        () => properties.selectDriver([fake]),
        throwsA(
          _failure(
            property: 'spring.datasource.driver',
            message: 'the drivers there are: fake: fake',
            action: 'oracle package',
          ),
        ),
      );
    });

    test('two drivers for one scheme ask for a choice', () {
      final properties = _properties({'spring.datasource.url': 'fake:x'});
      expect(
        () => properties.selectDriver([fake, _TwinDriver()]),
        throwsA(
          _failure(
            property: 'spring.datasource.url',
            message: 'fake, twin all handle the scheme "fake"',
            action: 'spring.datasource.driver',
          ),
        ),
      );
    });

    test('a scheme with a known package says which to add', () {
      final properties = _properties({
        'spring.datasource.url': 'postgresql://db:5432/app',
      });
      expect(
        () => properties.selectDriver([fake]),
        throwsA(
          _failure(
            property: 'spring.datasource.url',
            message: 'no driver of the postgres package',
            action: 'generated code is older than the pubspec',
          ),
        ),
      );
      expect(
        () => properties.selectDriver(const []),
        throwsA(
          isA<DataSourceConfigurationException>().having(
            (e) => e.message,
            'message',
            contains('its generated code has no driver'),
          ),
        ),
      );
    });

    test('a scheme nobody knows says to check the URL', () {
      final properties = _properties({'spring.datasource.url': 'mystery:x'});
      expect(
        () => properties.createPool([fake]),
        throwsA(
          _failure(
            property: 'spring.datasource.url',
            message: 'no driver handles the scheme "mystery"',
            action: 'write a JdbcDriver bean',
          ),
        ),
      );
    });
  });
}
