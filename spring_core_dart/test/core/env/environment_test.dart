import 'package:spring_core_dart/src/core/convert/generic_conversion_service.dart';
import 'package:spring_core_dart/src/core/env/env_exceptions.dart';
import 'package:spring_core_dart/src/core/env/environment.dart';
import 'package:spring_core_dart/src/core/env/profiles.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/env/system_environment_property_source.dart';
import 'package:test/test.dart';

StandardEnvironment env(
  Map<String, Object?> props, {
  Map<String, String> system = const {},
}) =>
    StandardEnvironment(systemEnvironment: system)
      ..propertySources.addFirst(MapPropertySource('test', props));

void main() {
  group('properties', () {
    test('lookup, defaults, typed values, nested placeholders', () {
      final e = env({
        'app.name': 'NEON',
        'app.title': r'${app.name} Harness',
        'app.port': '8080',
        'app.timeout': '5s',
        'app.tags': 'a, b',
        'app.number': 7,
        'app.blank': '',
      });
      expect(e.getProperty('app.title'), 'NEON Harness');
      expect(e.getProperty('missing', defaultValue: 'x'), 'x');
      expect(e.getPropertyAs<int>('app.port'), 8080);
      expect(
        e.getPropertyAs<Duration>('app.timeout'),
        const Duration(seconds: 5),
      );
      expect(e.getPropertyAs<List<String>>('app.tags'), ['a', 'b']);
      expect(e.getPropertyAs<int>('app.number'), 7);
      expect(e.getProperty('app.number'), '7');
      expect(e.getPropertyAs<int>('missing', defaultValue: 3), 3);
      expect(e.getPropertyAs<int>('app.blank', defaultValue: 9), 9);
      expect(e.getRequiredPropertyAs<int>('app.port'), 8080);
      expect(e.getRequiredProperty('app.name'), 'NEON');
      expect(e.containsProperty('app.name'), isTrue);
      expect(e.containsProperty('nope'), isFalse);
    });

    test('containsProperty for null and empty values; lists read as a,b', () {
      final e = env({
        'app.null': null,
        'app.empty': '',
        'app.list': ['a', 'b'],
      });
      expect(e.containsProperty('app.null'), isTrue);
      expect(e.containsProperty('app.empty'), isTrue);
      expect(e.containsProperty('app.none'), isFalse);
      expect(e.getProperty('app.list'), 'a,b');
    });

    test('required property missing', () {
      final e = env({});
      expect(
        () => e.getRequiredProperty('x'),
        throwsA(
          isA<MissingPropertyException>()
              .having((e) => e.key, 'key', 'x')
              .having((e) => e.toString(), 'text', contains("'x'")),
        ),
      );
    });

    test('unresolvable nested placeholder: strict and lenient', () {
      final e = env({'v': r'${nope}'});
      expect(
        () => e.getProperty('v'),
        throwsA(isA<PlaceholderResolutionException>()),
      );
      e.ignoreUnresolvableNestedPlaceholders = true;
      expect(e.getProperty('v'), r'${nope}');
    });

    test('resolvePlaceholders vs resolveRequiredPlaceholders', () {
      final e = env({'a': '1'});
      expect(e.resolvePlaceholders(r'${a}-${b}'), r'1-${b}');
      expect(
        () => e.resolveRequiredPlaceholders(r'${a}-${b}'),
        throwsA(isA<PlaceholderResolutionException>()),
      );
    });

    test('custom placeholder syntax', () {
      final e = env({'a': '1', 'b': 'two'})
        ..placeholderPrefix = '%{'
        ..placeholderSuffix = '}'
        ..valueSeparator = '?'
        ..escapeCharacter = '~';
      expect(e.resolveRequiredPlaceholders('%{a} %{x?d} ~%{b}'), '1 d %{b}');
      e.valueSeparator = null;
      e.escapeCharacter = null;
      expect(e.resolvePlaceholders('%{x?d}'), '%{x?d}');
    });

    test('required properties validation lists every missing key', () {
      final e = env({'a': '1'})..setRequiredProperties(['a', 'b', 'c']);
      expect(
        e.validateRequiredProperties,
        throwsA(
          isA<MissingRequiredPropertiesException>()
              .having((e) => e.missingRequiredProperties, 'missing', ['b', 'c'])
              .having((e) => e.toString(), 'text', contains('[b, c]')),
        ),
      );
      e.propertySources.addLast(
        const MapPropertySource('more', {'b': 1, 'c': 2}),
      );
      expect(e.validateRequiredProperties, returnsNormally);
    });

    test('custom conversion service', () {
      final e = env({'a': '1'})..conversionService = GenericConversionService();
      expect(e.conversionService, isA<GenericConversionService>());
      expect(() => e.getPropertyAs<int>('a'), throwsA(anything));
    });

    test('system environment is the lowest default source', () {
      final e = env(
        {'server.port': '1'},
        system: {'SERVER_PORT': '2', 'X_Y': 'z'},
      );
      expect(e.getProperty('server.port'), '1');
      expect(e.getProperty('x.y'), 'z');
      expect(e.systemEnvironment, {'SERVER_PORT': '2', 'X_Y': 'z'});
      expect(e.propertySources.last, isA<SystemEnvironmentPropertySource>());
    });

    test('process environment is used by default', () {
      expect(StandardEnvironment().systemEnvironment, isNotEmpty);
    });
  });

  group('profiles', () {
    test('default profile applies only when nothing is active', () {
      final e = env({});
      expect(e.activeProfiles, isEmpty);
      expect(e.defaultProfiles, ['default']);
      expect(e.matchesProfiles(['default']), isTrue);
      e.addActiveProfile('dev');
      expect(e.matchesProfiles(['default']), isFalse);
      expect(e.matchesProfiles(['dev']), isTrue);
    });

    test('from spring.profiles.active / default properties', () {
      final e = env({
        'spring.profiles.active': 'dev, eu',
        'spring.profiles.default': 'local',
      });
      expect(e.activeProfiles, ['dev', 'eu']);
      expect(e.defaultProfiles, ['local']);
      expect(e.matchesProfiles(['dev & eu']), isTrue);
    });

    test('blank property values are ignored', () {
      final e = env({
        'spring.profiles.active': ' ',
        'spring.profiles.default': '',
      });
      expect(e.activeProfiles, isEmpty);
      expect(e.defaultProfiles, ['default']);
    });

    test('explicit profiles win over the property', () {
      final e = env({'spring.profiles.active': 'dev'})
        ..setActiveProfiles(['prod']);
      expect(e.activeProfiles, ['prod']);
      e.addActiveProfile('eu');
      expect(e.activeProfiles, ['prod', 'eu']);
    });

    test('addActiveProfile keeps property profiles', () {
      final e = env({'spring.profiles.active': 'dev'})..addActiveProfile('eu');
      expect(e.activeProfiles, ['dev', 'eu']);
    });

    test('custom default profiles', () {
      final e = env({})..setDefaultProfiles(['local']);
      expect(e.matchesProfiles(['local']), isTrue);
      expect(e.matchesProfiles(['default']), isFalse);
    });

    test('invalid profile names', () {
      final e = env({});
      expect(() => e.addActiveProfile(' '), throwsArgumentError);
      expect(() => e.setActiveProfiles(['!x']), throwsArgumentError);
      expect(() => e.setDefaultProfiles(['']), throwsArgumentError);
      expect(() => e.isProfileActive('!dev'), throwsArgumentError);
    });

    test('merge with a parent', () {
      final parent = env({'p': 'parent', 'shared': 'parent'})
        ..setActiveProfiles(['parent'])
        ..setDefaultProfiles(['pd']);
      final child = env({'shared': 'child'})..merge(parent);
      expect(
        child.getProperty('p'),
        isNull,
        reason: 'parent source named "test" is already present',
      );
      expect(child.activeProfiles, ['parent']);
      expect(child.defaultProfiles, ['pd']);

      final other = StandardEnvironment(systemEnvironment: {})
        ..propertySources.addFirst(const MapPropertySource('child', {}))
        ..merge(parent);
      expect(other.getProperty('p'), 'parent');
    });

    test('merge with a parent without profiles', () {
      final parent = StandardEnvironment(systemEnvironment: {})
        ..setDefaultProfiles([]);
      final child = env({})..merge(parent);
      expect(child.activeProfiles, isEmpty);
      expect(child.defaultProfiles, ['default']);
    });

    test('toString', () {
      expect(env({}).toString(), contains('activeProfiles'));
    });
  });

  group('Profiles expressions', () {
    bool matches(String expression, Set<String> active) =>
        Profiles.of([expression]).matches(active.contains);

    test('operators', () {
      expect(matches('a', {'a'}), isTrue);
      expect(matches('!a', {'a'}), isFalse);
      expect(matches('!!a', {'a'}), isTrue);
      expect(matches('a & b', {'a'}), isFalse);
      expect(matches('a & b', {'a', 'b'}), isTrue);
      expect(matches('a | b', {'b'}), isTrue);
      expect(matches('a & (b | c)', {'a', 'c'}), isTrue);
      expect(matches('(a & b) | c', {'c'}), isTrue);
      expect(matches('!(a | b)', {}), isTrue);
      expect(matches('a&b&c', {'a', 'b', 'c'}), isTrue);
      expect(matches('a|b|c', {'x'}), isFalse);
      expect(matches('(a)', {'a'}), isTrue);
    });

    test('several expressions are OR-ed', () {
      expect(Profiles.of(['a', 'b']).matches({'b'}.contains), isTrue);
      expect(Profiles.of(['a', 'b']).matches({'c'}.contains), isFalse);
    });

    test('malformed expressions', () {
      for (final bad in [
        '',
        '  ',
        'a & b | c',
        'a |',
        '& a',
        '(a',
        'a)',
        '()',
        'a b',
        '!',
      ]) {
        expect(() => Profiles.of([bad]), throwsArgumentError, reason: bad);
      }
      expect(() => Profiles.of([]), throwsArgumentError);
    });
  });
}
