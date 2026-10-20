import 'package:spring_core_dart/src/core/env/command_line_property_source.dart';
import 'package:spring_core_dart/src/core/env/mutable_property_sources.dart';
import 'package:spring_core_dart/src/core/env/property_source.dart';
import 'package:spring_core_dart/src/core/env/system_environment_property_source.dart';
import 'package:test/test.dart';

class _Plain extends AbstractPropertySource<Object> {
  _Plain(String name, this.values) : super(name, values);
  final Map<String, Object?> values;
  @override
  Object? getProperty(String name) => values[name];
}

void main() {
  group('MapPropertySource', () {
    test('lookup, contains, names, equality by name', () {
      const source = MapPropertySource('m', {'a': 1, 'n': null});
      expect(source.getProperty('a'), 1);
      expect(source.containsProperty('n'), isTrue);
      expect(source.containsProperty('x'), isFalse);
      expect(source.propertyNames, ['a', 'n']);
      expect(source, const MapPropertySource('m', {}));
      expect(source.hashCode, 'm'.hashCode);
      expect(source.toString(), contains('name=m'));
    });

    test('base containsProperty uses getProperty', () {
      final plain = _Plain('p', {'a': 1});
      expect(plain.containsProperty('a'), isTrue);
      expect(plain.containsProperty('b'), isFalse);
    });
  });

  group('CompositePropertySource', () {
    test('searches in order and merges names', () {
      final composite = CompositePropertySource('c')
        ..addPropertySource(
          const MapPropertySource('low', {'a': 'low', 'b': 'b'}),
        )
        ..addFirstPropertySource(const MapPropertySource('high', {'a': 'high'}))
        ..addPropertySource(_Plain('plain', {'z': 'z'}));
      expect(composite.getProperty('a'), 'high');
      expect(composite.getProperty('z'), 'z');
      expect(composite.getProperty('none'), isNull);
      expect(composite.containsProperty('b'), isTrue);
      expect(composite.containsProperty('none'), isFalse);
      expect(composite.propertyNames, ['a', 'b']);
      expect(composite.propertySources, hasLength(3));
    });
  });

  group('SystemEnvironmentPropertySource', () {
    const env = SystemEnvironmentPropertySource('env', {
      'MY_PROP_NAME': '1',
      'SERVER_PORT': '8080',
      'lower.case': 'lc',
      'APP_FEATUREFLAG': 'on',
    });

    test('relaxed names', () {
      expect(env.getProperty('my.prop-name'), '1');
      expect(env.getProperty('my.prop_name'), '1');
      expect(env.getProperty('MY_PROP_NAME'), '1');
      expect(env.getProperty('server.port'), '8080');
      expect(env.getProperty('lower.case'), 'lc');
      expect(env.getProperty('app.feature-flag'), 'on');
      expect(env.getProperty('nope'), isNull);
      expect(env.containsProperty('server.port'), isTrue);
      expect(env.containsProperty('nope'), isFalse);
      expect(env.resolvePropertyName('server.port'), 'SERVER_PORT');
    });
  });

  group('SimpleCommandLinePropertySource', () {
    test('options, flags, repeats and non-option args', () {
      final source = SimpleCommandLinePropertySource([
        '--server.port=9000',
        '--debug',
        '--tag=a',
        '--tag=b',
        '--eq=x=y',
        'file.txt',
        'other',
      ]);
      expect(source.name, SimpleCommandLinePropertySource.defaultName);
      expect(source.getProperty('server.port'), '9000');
      expect(source.getProperty('debug'), '');
      expect(source.getProperty('tag'), 'a,b');
      expect(source.getProperty('eq'), 'x=y');
      expect(source.getOptionValues('tag'), ['a', 'b']);
      expect(source.getOptionValues('missing'), isNull);
      expect(source.containsProperty('debug'), isTrue);
      expect(source.containsProperty('missing'), isFalse);
      expect(source.nonOptionArgs, ['file.txt', 'other']);
      expect(source.getProperty('nonOptionArgs'), 'file.txt,other');
      expect(source.containsProperty('nonOptionArgs'), isTrue);
      expect(source.propertyNames, ['server.port', 'debug', 'tag', 'eq']);
    });

    test('no non-option args and custom name', () {
      final source = SimpleCommandLinePropertySource(['--a=1'], name: 'cli');
      expect(source.name, 'cli');
      expect(source.getProperty('nonOptionArgs'), isNull);
      expect(source.containsProperty('nonOptionArgs'), isFalse);
    });

    test('invalid syntax', () {
      expect(
        () => SimpleCommandLinePropertySource(['--=x']),
        throwsArgumentError,
      );
      expect(
        () => SimpleCommandLinePropertySource(['--']),
        throwsArgumentError,
      );
    });
  });

  group('MutablePropertySources', () {
    const a = MapPropertySource('a', {'k': 'a'});
    const b = MapPropertySource('b', {'k': 'b'});
    const c = MapPropertySource('c', {'k': 'c'});

    List<String> names(MutablePropertySources s) => [for (final p in s) p.name];

    test('ordering operations', () {
      final sources = MutablePropertySources([a])
        ..addFirst(b)
        ..addLast(c);
      expect(names(sources), ['b', 'a', 'c']);
      sources.addBefore('a', const MapPropertySource('x', {}));
      expect(names(sources), ['b', 'x', 'a', 'c']);
      sources.addAfter('a', const MapPropertySource('y', {}));
      expect(names(sources), ['b', 'x', 'a', 'y', 'c']);
      expect(sources.precedenceOf(a), 2);
      expect(sources.precedenceOf(const MapPropertySource('zz', {})), -1);
    });

    test('adding an existing name moves it', () {
      final sources = MutablePropertySources([a, b, c])..addFirst(c);
      expect(names(sources), ['c', 'a', 'b']);
      sources.addBefore('a', b);
      expect(names(sources), ['c', 'b', 'a']);
    });

    test('get, contains, remove, replace', () {
      final sources = MutablePropertySources([a, b]);
      expect(sources.get('a'), same(a));
      expect(sources.get('zz'), isNull);
      expect(sources.containsSource('b'), isTrue);
      sources.replace('a', c);
      expect(names(sources), ['c', 'b']);
      expect(sources.remove('b'), same(b));
      expect(sources.remove('b'), isNull);
      expect(sources.toString(), contains('name=c'));
    });

    test('errors', () {
      final sources = MutablePropertySources([a]);
      expect(() => sources.addBefore('zz', b), throwsArgumentError);
      expect(() => sources.addAfter('a', a), throwsArgumentError);
      expect(() => sources.replace('zz', b), throwsArgumentError);
    });

    test('iteration is a snapshot', () {
      final sources = MutablePropertySources([a, b]);
      for (final source in sources) {
        if (source.name == 'a') {
          sources.addLast(c);
        }
      }
      expect(names(sources), ['a', 'b', 'c']);
    });
  });
}
