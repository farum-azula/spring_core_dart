import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

/// A resource that, like a Flutter asset, can only be read asynchronously.
class _AsyncResource extends AbstractResource {
  _AsyncResource(this.description, this.content);

  @override
  final String description;
  final String? content;

  @override
  bool exists() => content != null;

  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(utf8.encode(content!));
}

void main() {
  late Directory temp;
  late String root;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('scd_config_fixes_');
    root = temp.path;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  void write(String path, String content) => File('$root/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  StandardEnvironment env([
    Map<String, Object?> props = const {},
    Map<String, String> system = const {},
  ]) =>
      StandardEnvironment(systemEnvironment: system)
        ..propertySources.addFirst(MapPropertySource('cli', props));

  void process(
    StandardEnvironment environment, {
    List<PropertySourceLoader> loaders = const [
      PropertiesPropertySourceLoader(),
    ],
  }) => ConfigDataEnvironment(
    environment,
    defaultLocations: ['optional:file:$root/'],
    loaders: loaders,
  ).processAndApplySync();

  group('imports and guards', () {
    test('an optional import with an unresolvable placeholder is skipped', () {
      write('application.properties', r'''
spring.config.import=optional:file:${missing.dir}/x.properties
a=1
''');
      final environment = env();
      process(environment);
      expect(environment.getProperty('a'), '1');
    });

    test('a mandatory import with an unresolvable placeholder is not '
        'found', () {
      write(
        'application.properties',
        r'spring.config.import=file:${missing.dir}/x.properties',
      );
      expect(
        () => process(env()),
        throwsA(isA<ConfigDataResourceNotFoundException>()),
      );
    });

    test("the command line beats a file's own value in its imports and "
        'guards', () {
      write('application.properties', '''
dir=file
spring.config.import=file:$root/\${dir}.properties
#---
spring.config.activate.on-profile=\${guard}
guard=nope
guarded=yes
''');
      write('file.properties', 'from=file');
      write('cli.properties', 'from=cli');
      final environment = env({
        'dir': 'cli',
        'guard': 'p',
        'spring.profiles.active': 'p',
      });
      process(environment);
      expect(environment.getProperty('from'), 'cli');
      expect(environment.getProperty('guarded'), 'yes');
    });
  });

  group('indexed keys', () {
    test('a higher source replaces a whole list, like Boot binding', () {
      write('application.properties', '''
spring.profiles.active[0]=a
spring.profiles.active[1]=b
''');
      final environment = env({'spring.profiles.active[0]': 'c'});
      process(environment);
      expect(environment.activeProfiles, ['c']);
    });

    test('environment variables with indexes', () {
      write('application.properties', 'spring.profiles.active=a');
      write('x.properties', 'fromImport=1');
      final environment = env(const {}, {
        'SPRING_PROFILES_INCLUDE_0_': 'inc',
        'SPRING_CONFIG_IMPORT_0_': 'file:$root/x.properties',
      });
      process(environment);
      expect(environment.activeProfiles, ['inc', 'a']);
      expect(environment.getProperty('fromImport'), '1');
    });
  });

  group('encoding', () {
    test('.properties files in ISO-8859-1', () {
      File('$root/application.properties')
          .writeAsBytesSync(latin1.encode('greeting=Grüße'));
      final environment = env();
      process(
        environment,
        loaders: const [PropertiesPropertySourceLoader(encoding: latin1)],
      );
      expect(environment.getProperty('greeting'), 'Grüße');
    });

    test('@PropertySource encoding', () {
      File('$root/a.properties').writeAsBytesSync(latin1.encode('x=é'));
      final environment = env();
      PropertySourceProcessor(
        environment,
        DefaultResourceLoader(),
      ).processPropertySource([
        'file:$root/a.properties',
      ], encoding: 'ISO-8859-1');
      expect(environment.getProperty('x'), 'é');
      expect(
        () => PropertySourceProcessor(
          environment,
          DefaultResourceLoader(),
        ).processPropertySource(['file:$root/a.properties'], encoding: 'x'),
        throwsArgumentError,
      );
    });
  });

  group('locations', () {
    test('a mandatory wildcard location without subdirectories fails', () {
      Directory('$root/config').createSync();
      final environment = env({
        'spring.config.location': 'file:$root/config/*/',
      });
      expect(
        () => process(environment),
        throwsA(
          isA<ConfigDataLocationNotFoundException>().having(
            (e) => e.toString(),
            'message',
            contains('contains no subdirectories'),
          ),
        ),
      );
      // Optional, or with a subdirectory: fine.
      process(env({'spring.config.location': 'optional:file:$root/config/*/'}));
      write('config/a/application.properties', 'a=1');
      final found = env({'spring.config.location': 'file:$root/config/*/'});
      process(found);
      expect(found.getProperty('a'), '1');
    });

    test('package: locations are files of the package', () {
      final resource = DefaultResourceLoader().getResource(
        'package:spring_core_dart/core.dart',
      );
      expect(resource, isA<FileSystemResource>());
      expect(resource.readAsStringSync(), contains('library;'));
      expect(
        DefaultResourceLoader()
            .getResource('package:no_such_pkg/a.yml')
            .exists(),
        isFalse,
      );
    });
  });

  group('random values', () {
    test('random.* like Boot', () {
      final source = RandomValuePropertySource(random: math.Random(1));
      expect(source.getProperty('other'), isNull);
      expect(source.getProperty('random.int'), isA<int>());
      expect(source.getProperty('random.long'), isA<int>());
      for (var i = 0; i < 50; i++) {
        expect(source.getProperty('random.int(10)'), inInclusiveRange(0, 9));
        expect(source.getProperty('random.int[5,8]'), inInclusiveRange(5, 7));
        expect(
          source.getProperty('random.long[10000000000,10000000005]'),
          inInclusiveRange(10000000000, 10000000004),
        );
      }
      expect(
        source.getProperty('random.uuid'),
        matches(
          RegExp(
            // A string that cannot be split without changing it.
            // ignore: lines_longer_than_80_chars
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(
        source.getProperty('random.value'),
        matches(RegExp(r'^[0-9a-f]{32}$')),
      );
      expect(() => source.getProperty('random.int(0)'), throwsStateError);
      expect(() => source.getProperty('random.int[5,5]'), throwsStateError);
    });

    test('added after the system environment, usable in config files', () {
      write('application.properties', r'app.id=${random.uuid}');
      final environment = env();
      RandomValuePropertySource.addToEnvironment(environment);
      RandomValuePropertySource.addToEnvironment(environment);
      expect(
        [for (final s in environment.propertySources) s.name],
        [
          'cli',
          'systemProperties',
          'systemEnvironment',
          'random',
        ].where((n) => environment.propertySources.containsSource(n)),
      );
      process(environment);
      expect(environment.getProperty('app.id'), hasLength(36));
    });
  });

  group('async @PropertySource', () {
    test('async-only resources are preloaded, then processed', () async {
      final loader = DefaultResourceLoader(
        protocolResolvers: [
          FunctionProtocolResolver(
            (location, _) => location.startsWith('asset:')
                ? _AsyncResource(
                    location,
                    location == 'asset:a.properties' ? 'a=1' : null,
                  )
                : null,
          ),
        ],
      );
      final environment = env();
      final processor = PropertySourceProcessor(environment, loader);
      expect(
        () => processor.processPropertySource(['asset:a.properties']),
        throwsStateError,
      );
      await processor.preload(['asset:a.properties', 'asset:none', r'${x}']);
      processor.processPropertySource(['asset:a.properties']);
      expect(environment.getProperty('a'), '1');
    });

    test('refreshAsync preloads @PropertySource assets', () async {
      final context =
          AnnotationConfigApplicationContext([
            BeanModule(
              'assets',
              const [],
              propertySources: const [
                PropertySourceDeclaration(['asset:a.properties']),
              ],
            ),
          ], environment: env())..addProtocolResolver(
            FunctionProtocolResolver(
              (location, _) => location == 'asset:a.properties'
                  ? _AsyncResource(location, 'fromAsset=yes')
                  : null,
            ),
          );
      await context.refreshAsync();
      expect(context.environment.getProperty('fromAsset'), 'yes');
      context.close();
    });
  });
}
