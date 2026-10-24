import 'dart:convert';
import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

enum Color { red, darkBlue }

class Placed {
  Placed(this.id);
  final int id;
}

class Shipped {
  Shipped(this.id);
  final int id;
}

class Audit {}

void main() {
  group('@EventListener results with their declared type', () {
    test('reach PayloadApplicationEvent<R> listeners', () {
      final seen = <String>[];
      final context = AnnotationConfigApplicationContext([
        BeanModule('m', [
          BeanDefinition<Audit>(
            name: 'audit',
            eventListeners: [
              EventListenerMethod.of<Audit, Placed>(
                'Audit.onPlaced',
                (bean, event) => Shipped(event.id),
                resultType: const EventResultType<Shipped>(),
              ),
              EventListenerMethod.of<Audit, int>(
                'Audit.onNumber',
                (bean, event) => [Shipped(event), Shipped(event + 1)],
                resultType: const EventResultType<Shipped>(),
              ),
            ],
            create: (_) => Audit(),
          ),
        ]),
      ]);
      context
        ..addListener<PayloadApplicationEvent<Shipped>>(
          (event) => seen.add('payload ${event.payload.id}'),
        )
        ..addListener<Shipped>((event) => seen.add('plain ${event.id}'))
        ..refresh();
      addTearDown(context.close);
      context.publishEvent(Placed(1));
      context.publishEvent(5);
      expect(seen, [
        'payload 1',
        'plain 1',
        'payload 5',
        'plain 5',
        'payload 6',
        'plain 6',
      ]);
    });
  });

  test('applicationListeners lists the listeners added', () {
    final context = AnnotationConfigApplicationContext([]);
    final listener = ApplicationListenerAdapter.of<String>((_) {});
    context.addApplicationListener(listener);
    expect(context.applicationListeners, [listener]);
    context.removeApplicationListener(listener);
    expect(context.applicationListeners, isEmpty);
  });

  test('ConfigurableListableBeanFactory.registerAlias', () {
    final context = AnnotationConfigApplicationContext([
      BeanModule('m', [
        BeanDefinition<Audit>(name: 'audit', create: (_) => Audit()),
      ]),
    ])..refresh();
    addTearDown(context.close);
    final ConfigurableListableBeanFactory factory = context.beanFactory;
    factory.registerAlias('audit', 'auditor');
    expect(context.getBeanByName('auditor'), same(context.getBean<Audit>()));
  });

  group('converters', () {
    final service = DefaultConversionService();

    test('object → one-element collection', () {
      expect(service.convert<List<int>>(5), [5]);
      expect(service.convert<Set<String>>(3), {'3'});
      expect(service.convert<List<int>>('1,2'), [1, 2]);
    });

    test('Map → Map, keys and values converted', () {
      expect(service.convert<Map<String, int>>({'a': '1', 2: 3}), {
        'a': 1,
        '2': 3,
      });
      expect(service.convert<Map<String, Object?>>({1: true}), {'1': true});
    });

    test('String → Encoding and back', () {
      expect(service.convert<Encoding>('UTF-8'), utf8);
      expect(service.convert<Encoding>('latin1'), latin1);
      expect(service.convert<String>(utf8), 'utf-8');
      expect(
        () => service.convert<Encoding>('nope'),
        throwsA(isA<ConversionFailedException>()),
      );
    });

    test('BigInt → int fails on overflow; num → BigInt', () {
      expect(service.convert<int>(BigInt.from(42)), 42);
      expect(
        () => service.convert<int>(BigInt.parse('99999999999999999999')),
        throwsA(isA<ConversionFailedException>()),
      );
      expect(service.convert<double>(BigInt.two), 2.0);
      expect(service.convert<BigInt>(7), BigInt.from(7));
    });

    test('enum → String is the name, also in placeholders', () {
      expect(service.convert<String>(Color.darkBlue), 'darkBlue');
      final environment = StandardEnvironment(systemEnvironment: {})
        ..propertySources.addFirst(
          MapPropertySource('enums', {'color': Color.red}),
        );
      expect(environment.getProperty('color'), 'red');
      expect(environment.resolvePlaceholders(r'is ${color}'), 'is red');
    });

    test('addEnum adds List<E> and Set<E>', () {
      final registry = DefaultConversionService()..addEnum(Color.values);
      expect(registry.convert<List<Color>>('red, dark-blue'), [
        Color.red,
        Color.darkBlue,
      ]);
      expect(registry.convert<Set<Color>>(['red']), {Color.red});
    });
  });

  group('resources', () {
    test('embedded classpath resources have a filename and createRelative', () {
      ClasspathResources.registerAll(const {
        'fixes/conf/app.properties': EmbeddedResource.text('a=1'),
        'fixes/conf/other.properties': EmbeddedResource.text('b=2'),
      });
      final resource = DefaultResourceLoader().getResource(
        'classpath:fixes/conf/app.properties',
      );
      expect(resource.filename, 'app.properties');
      final sibling = resource.createRelative('other.properties');
      expect(sibling.readAsStringSync(), 'b=2');
      expect(sibling.filename, 'other.properties');
    });

    test('http: and https: locations are UrlResources', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        if (request.uri.path == '/conf/app.properties') {
          request.response.write('a=1');
        } else {
          request.response.statusCode = 404;
        }
        request.response.close();
      });
      final base = 'http://127.0.0.1:${server.port}';
      final resource = DefaultResourceLoader().getResource(
        '$base/conf/app.properties',
      );
      expect(resource, isA<UrlResource>());
      expect(resource.filename, 'app.properties');
      expect(resource.description, 'URL [$base/conf/app.properties]');
      expect(resource.supportsSyncRead, isFalse);
      expect(await resource.readAsString(), 'a=1');
      final missing = resource.createRelative('/missing.properties');
      expect(missing.uri.toString(), '$base/conf/missing.properties');
      await expectLater(missing.readAsBytes(), throwsA(isA<HttpException>()));
      expect(
        DefaultResourceLoader().getResource('https://example.com/a'),
        isA<UrlResource>(),
      );
    });
  });

  group('URL resources are probed with HEAD (404 is not found)', () {
    late String base;
    final heads = <String>[];

    setUp(() async {
      heads.clear();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        if (request.method == 'HEAD') {
          heads.add(request.uri.path);
        }
        switch (request.uri.path) {
          case '/app.properties':
            request.response.write('from.url=1');
          case '/no-head.properties':
            if (request.method == 'HEAD') {
              request.response.statusCode = HttpStatus.methodNotAllowed;
            } else {
              request.response.write('b=2');
            }
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        request.response.close();
      });
      base = 'http://127.0.0.1:${server.port}';
    });

    test('existsAsync', () async {
      final loader = DefaultResourceLoader();
      final found = loader.getResource('$base/app.properties') as UrlResource;
      final missing = loader.getResource('$base/missing.properties');
      final noHead = loader.getResource('$base/no-head.properties');
      expect(found.exists(), isTrue); // cannot ask synchronously
      expect(await found.existsAsync(), isTrue);
      expect(await (missing as UrlResource).existsAsync(), isFalse);
      // 405 for HEAD: asked again with GET, like Spring.
      expect(await (noHead as UrlResource).existsAsync(), isTrue);
      expect(
        await UrlResource(Uri.parse('http://127.0.0.1:1/x')).existsAsync(),
        isFalse,
      );
    });

    StandardEnvironment env(Map<String, Object?> props) =>
        StandardEnvironment(systemEnvironment: {})
          ..propertySources.addFirst(MapPropertySource('cli', props));

    ConfigDataEnvironment config(StandardEnvironment environment) =>
        ConfigDataEnvironment(
          environment,
          defaultLocations: const [],
          loaders: const [PropertiesPropertySourceLoader()],
        );

    test('spring.config.import of a URL skips the missing profile variants '
        'and missing optional URLs', () async {
      final e = env({
        'spring.profiles.active': 'dev',
        'spring.config.import':
            '$base/app.properties,optional:$base/missing.properties',
      });
      await config(e).processAndApply();
      expect(e.getProperty('from.url'), '1');
      expect(heads, contains('/app-dev.properties'));
      expect(heads, contains('/missing.properties'));
    });

    test('a missing mandatory URL import fails', () async {
      final e = env({'spring.config.import': '$base/missing.properties'});
      await expectLater(
        config(e).processAndApply(),
        throwsA(isA<ConfigDataResourceNotFoundException>()),
      );
    });

    test('@PropertySource(ignoreResourceNotFound: true) skips a 404; '
        'without it the refresh fails', () async {
      AnnotationConfigApplicationContext context(bool ignore) =>
          AnnotationConfigApplicationContext([
            BeanModule(
              'm',
              const [],
              propertySources: [
                PropertySourceDeclaration([
                  '$base/missing.properties',
                  '$base/app.properties',
                ], ignoreResourceNotFound: ignore),
              ],
            ),
          ], environment: StandardEnvironment(systemEnvironment: {}));
      final lenient = context(true);
      await lenient.refreshAsync();
      expect(lenient.environment.getProperty('from.url'), '1');
      lenient.close();
      final strict = context(false);
      await expectLater(
        strict.refreshAsync(),
        throwsA(isA<PropertySourceNotFoundException>()),
      );
    });
  });

  test('@PropertySource with a file pattern loads every match', () {
    final directory = Directory.systemTemp.createTempSync('scd_ps_pattern_');
    addTearDown(() => directory.deleteSync(recursive: true));
    File('${directory.path}/a.properties').writeAsStringSync('a=1\nshared=a');
    File('${directory.path}/b.properties').writeAsStringSync('b=2\nshared=b');
    File('${directory.path}/c.txt').writeAsStringSync('c=3');
    final context = AnnotationConfigApplicationContext([
      BeanModule(
        'm',
        const [],
        propertySources: [
          PropertySourceDeclaration(['file:${directory.path}/*.properties']),
          PropertySourceDeclaration([
            'file:${directory.path}/none/*.properties',
          ]),
        ],
      ),
    ], environment: StandardEnvironment(systemEnvironment: {}))..refresh();
    addTearDown(context.close);
    final environment = context.environment;
    expect(environment.getProperty('a'), '1');
    expect(environment.getProperty('b'), '2');
    expect(environment.getProperty('c'), isNull);
    expect(environment.getProperty('shared'), 'b', reason: 'the last wins');
  });

  test('YAML integers beyond 64 bits stay exact', () {
    final source = const YamlPropertySourceLoader()
        .load('y', 'big: 99999999999999999999\nsmall: 42\nhex: 0x10\n')
        .single;
    expect(source.getProperty('big'), BigInt.parse('99999999999999999999'));
    expect(source.getProperty('small'), 42);
    expect(source.getProperty('hex'), 16);
    final environment = StandardEnvironment(systemEnvironment: {})
      ..propertySources.addFirst(source);
    expect(environment.getProperty('big'), '99999999999999999999');
  });
}
