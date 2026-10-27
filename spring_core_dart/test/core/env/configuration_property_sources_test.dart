import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigurationPropertyName', () {
    test('canonical names', () {
      for (final valid in [
        'app.read-timeout',
        'app.hosts[0].name',
        'app.headers[X-Shop.Id]',
        'a1.b2',
        '',
      ]) {
        expect(ConfigurationPropertyName.isValid(valid), isTrue, reason: valid);
      }
      for (final invalid in [
        'app.readTimeout',
        'app.read_timeout',
        '.app',
        'app.',
        'app[0',
        'app.-x',
      ]) {
        expect(
          ConfigurationPropertyName.isValid(invalid),
          isFalse,
          reason: invalid,
        );
      }
      expect(
        () => ConfigurationPropertyName.of('app.readTimeout'),
        throwsA(isA<InvalidConfigurationPropertyNameException>()),
      );
    });

    test('relaxed equality of adapted names', () {
      final canonical = ConfigurationPropertyName.of('app.read-timeout');
      for (final form in [
        'app.readTimeout',
        'app.read_timeout',
        'APP.READ-TIMEOUT',
        'app.readtimeout',
      ]) {
        expect(
          ConfigurationPropertyName.adapt(form, '.'),
          canonical,
          reason: form,
        );
        expect(
          ConfigurationPropertyName.adapt(form, '.').hashCode,
          canonical.hashCode,
        );
      }
      expect(
        ConfigurationPropertyName.adapt('app.hosts.0', '.'),
        ConfigurationPropertyName.of('app.hosts[0]'),
      );
      // Indexes compare exactly.
      expect(
        ConfigurationPropertyName.of('map[X-Shop]') ==
            ConfigurationPropertyName.of('map[x-shop]'),
        isFalse,
      );
    });

    test('elements, parents and ancestors', () {
      final name = ConfigurationPropertyName.adapt('App.readTimeout[0]', '.');
      expect(name.numberOfElements, 3);
      expect(name.getElement(1), 'readTimeout');
      expect(
        name.getElement(1, form: ConfigurationPropertyNameForm.uniform),
        'readtimeout',
      );
      expect(name.isIndexed(2), isTrue);
      expect(name.isNumericIndex(2), isTrue);
      expect(name.isLastElementIndexed, isTrue);
      expect(name.toString(), 'app.readtimeout[0]');
      final app = ConfigurationPropertyName.of('app');
      expect(app.isAncestorOf(name), isTrue);
      expect(app.isParentOf(name), isFalse);
      expect(name.parent.isParentOf(name), isTrue);
      expect(app.append('[1]').toString(), 'app[1]');
      expect(app.append('x-y').toString(), 'app.x-y');
      expect(name.chop(1), app);
    });
  });

  group('ConfigurationPropertySources.attach', () {
    StandardEnvironment env(
      Map<String, Object?> properties, {
      Map<String, String> system = const {},
    }) {
      final environment = StandardEnvironment(systemEnvironment: system)
        ..propertySources.addFirst(MapPropertySource('app', properties));
      ConfigurationPropertySources.attach(environment);
      return environment;
    }

    test('canonical names find camelCase, underscore and upper-case keys', () {
      final e = env({
        'app.readTimeout': '5s',
        'app.logger_level': 'full',
        'APP.MAX-SIZE': '10',
      });
      expect(e.getProperty('app.read-timeout'), '5s');
      expect(
        e.getPropertyAs<Duration>('app.read-timeout'),
        const Duration(seconds: 5),
      );
      expect(e.getProperty('app.logger-level'), 'full');
      expect(e.getProperty('app.max-size'), '10');
      expect(e.containsProperty('app.read-timeout'), isTrue);
      // `${...}` placeholders go through the environment too.
      expect(e.resolvePlaceholders(r'${app.read-timeout}'), '5s');
      // Non-canonical names are looked up as written, as in Spring Boot.
      expect(e.getProperty('app.readTimeout'), '5s');
      expect(e.getProperty('app.maxSize'), isNull);
    });

    test('environment variables with dashes removed or as underscores', () {
      final e = env(
        const {},
        system: {
          'APP_READTIMEOUT': '1s',
          'APP_LOGGER_LEVEL': 'basic',
          'APP_HOSTS_0_': 'a',
          'APP_HOSTS_1': 'b',
        },
      );
      expect(e.getProperty('app.read-timeout'), '1s');
      expect(e.getProperty('app.logger-level'), 'basic');
      expect(e.getProperty('app.hosts[0]'), 'a');
      expect(e.getProperty('app.hosts[1]'), 'b');
    });

    test('the first source with the property wins, whatever its form', () {
      final e = StandardEnvironment(systemEnvironment: const {})
        ..propertySources.addFirst(
          const MapPropertySource('low', {'app.read-timeout': 'low'}),
        )
        ..propertySources.addFirst(
          const MapPropertySource('high', {'app.readTimeout': 'high'}),
        );
      ConfigurationPropertySources.attach(e);
      expect(e.getProperty('app.read-timeout'), 'high');
      // Within one source the canonical form wins.
      final both = env({
        'app.readTimeout': 'camel',
        'app.read-timeout': 'kebab',
      });
      expect(both.getProperty('app.read-timeout'), 'kebab');
    });

    test('later changes to a map source are seen', () {
      final map = <String, Object?>{};
      final e = env(map);
      expect(e.getProperty('app.my-prop'), isNull);
      map['app.myProp'] = 'x';
      expect(e.getProperty('app.my-prop'), 'x');
    });

    test('attaching twice keeps one source, first', () {
      final e = env(const {'a': '1'});
      e.propertySources.addFirst(const MapPropertySource('top', {}));
      ConfigurationPropertySources.attach(e);
      expect(e.propertySources.first.name, 'configurationProperties');
      expect(
        e.propertySources.where((s) => s.name == 'configurationProperties'),
        hasLength(1),
      );
      expect(ConfigurationPropertySources.isAttached(e), isTrue);
    });

    test('propertyNames gives adapted names for binders', () {
      final names = ConfigurationPropertySources.propertyNames(
        const MapPropertySource('m', {
          'app.headers.X-Shop': 'neon',
          'app.defaultRequestHeaders.X-Trace': 't',
        }),
      );
      final parent = ConfigurationPropertyName.of(
        'app.default-request-headers',
      );
      final children = names.keys.where(parent.isParentOf).toList();
      expect(children, hasLength(1));
      expect(children.single.getElement(2), 'X-Trace');
      expect(names[children.single], ['app.defaultRequestHeaders.X-Trace']);
    });
  });
}
