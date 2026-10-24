import 'dart:io';

import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

// Spring Boot config data behaviour: YAML out of the box, location groups,
// `config/*/` and relaxed names after processing.
void main() {
  late Directory temp;
  late String root;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('scd_boot_config_');
    root = temp.path;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  void write(String path, String content) => File('$root/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  StandardEnvironment env([Map<String, Object?> props = const {}]) =>
      StandardEnvironment(systemEnvironment: {})
        ..propertySources.addFirst(MapPropertySource('cli', props));

  // Spring Boot's file group, rooted at the temp directory.
  const fileGroup = [
    'optional:file:{root}/;optional:file:{root}/config/;'
        'optional:file:{root}/config/*/',
  ];

  void process(
    StandardEnvironment environment, {
    List<String> locations = fileGroup,
    ResourceLoader? resourceLoader,
  }) => ConfigDataEnvironment(
    environment,
    resourceLoader: resourceLoader,
    defaultLocations: [
      for (final location in locations) location.replaceAll('{root}', root),
    ],
  ).processAndApplySync();

  group('YAML out of the box', () {
    test('application.yml with nested maps, lists and profiles', () {
      write('application.yml', '''
spring:
  profiles:
    active: dev
app:
  name: demo
  port: 8080
  hosts: [a.example, b.example]
  servers:
    - name: one
  empty:
  nothing: ~
  text: |
    line 1
    line 2
  "[x.y]": kept
''');
      write('config/application-dev.yaml', 'app:\n  name: dev-demo\n');
      final e = env();
      process(e);
      expect(e.activeProfiles, ['dev']);
      expect(e.getProperty('app.name'), 'dev-demo');
      expect(e.getPropertyAs<int>('app.port'), 8080);
      expect(e.getProperty('app.port'), '8080');
      expect(e.getProperty('app.hosts[0]'), 'a.example');
      expect(e.getProperty('app.hosts[1]'), 'b.example');
      expect(e.getProperty('app.servers[0].name'), 'one');
      expect(e.getProperty('app.empty'), '');
      expect(e.containsProperty('app.empty'), isTrue);
      expect(e.getProperty('app.nothing'), '');
      expect(e.getProperty('app.text'), 'line 1\nline 2\n');
      expect(e.getProperty('app[x.y]'), 'kept');
      // @Value-style placeholders see YAML list items.
      expect(e.resolvePlaceholders(r'${app.hosts[1]}'), 'b.example');
    });

    test('multi-document YAML with on-profile, also as a list', () {
      write('application.yml', '''
mode: base
---
spring:
  config:
    activate:
      on-profile: [staging, prod]
mode: production
---
spring.config.activate.on-profile: "!prod"
other: not-prod
''');
      final prod = env({'spring.profiles.active': 'prod'});
      process(prod);
      expect(prod.getProperty('mode'), 'production');
      expect(prod.getProperty('other'), isNull);
      final dev = env({'spring.profiles.active': 'dev'});
      process(dev);
      expect(dev.getProperty('mode'), 'base');
      expect(dev.getProperty('other'), 'not-prod');
    });

    test('.properties beats .yml beats .yaml in the same location', () {
      write('application.properties', 'a=properties');
      write('application.yml', 'a: yml\nb: yml');
      write('application.yaml', 'a: yaml\nb: yaml\nc: yaml');
      final e = env();
      process(e);
      expect(e.getProperty('a'), 'properties');
      expect(e.getProperty('b'), 'yml');
      expect(e.getProperty('c'), 'yaml');
    });

    test('YAML imports and YAML lists for profiles and imports', () {
      write('application.yml', '''
spring:
  config:
    import:
      - extra.yml
      - optional:missing.yml
  profiles:
    include: [metrics, audit]
    group:
      prod: [db, mq]
''');
      write('extra.yml', 'extra: yes-it-is');
      write('application-db.yml', 'db: on');
      final e = env({'spring.profiles.active': 'prod'});
      process(e);
      expect(e.getProperty('extra'), 'yes-it-is');
      expect(e.activeProfiles, ['metrics', 'audit', 'prod', 'db', 'mq']);
      expect(e.getProperty('db'), 'on');
    });

    test('profile properties as YAML lists are rejected in profile files', () {
      write('application-dev.yml', 'spring.profiles.include: [x]');
      expect(
        () => process(env({'spring.profiles.active': 'dev'})),
        throwsA(isA<InvalidConfigDataPropertyException>()),
      );
    });

    test('embedded classpath YAML is found by the default locations', () {
      ClasspathResources.registerAll({
        'application.yml': const EmbeddedResource.text(
          'embedded:\n  greeting: hello\n',
        ),
        'config/application.yml': const EmbeddedResource.text(
          'embedded:\n  extra: config\n',
        ),
      }, owner: 'yamlDefaultTest');
      try {
        final e = env();
        ConfigDataEnvironment(e).processAndApplySync();
        expect(e.getProperty('embedded.greeting'), 'hello');
        expect(e.getProperty('embedded.extra'), 'config');
      } finally {
        ClasspathResources.registerAll(const {}, owner: 'yamlDefaultTest');
      }
    });

    test('invalid YAML fails with the location', () {
      write('application.yml', 'a: [1');
      expect(
        () => process(env()),
        throwsA(
          isA<ConfigDataLoadException>().having(
            (e) => e.location,
            'location',
            endsWith('application.yml'),
          ),
        ),
      );
    });

    test('@PropertySource-style factories still read .properties only', () {
      write('app.yml', 'app:\n  name: x\n');
      final source = const DefaultPropertySourceFactory().createPropertySource(
        null,
        EncodedResource(FileSystemResource('$root/app.yml')),
      );
      // Read as a properties file, like Spring's DefaultPropertySourceFactory.
      expect(source.getProperty('app.name'), isNull);
      expect(source.getProperty('name'), 'x');
    });
  });

  group('location groups', () {
    ResourceLoader packaged(Map<String, String> files) => DefaultResourceLoader(
      protocolResolvers: [InMemoryProtocolResolver('jar:', files)],
    );

    test('./application.properties beats a packaged profile file', () {
      write('application.properties', 'x=external\ny=external');
      final e = env({'spring.profiles.active': 'prod'});
      process(
        e,
        locations: ['optional:jar:/;optional:jar:/config/', ...fileGroup],
        resourceLoader: packaged({
          'application.properties': 'x=packaged\ny=packaged\nz=packaged',
          'application-prod.properties': 'x=packaged-prod\nz=packaged-prod',
        }),
      );
      expect(e.getProperty('x'), 'external');
      expect(e.getProperty('y'), 'external');
      expect(e.getProperty('z'), 'packaged-prod');
    });

    test('`,` separates groups and `;` locations of one group', () {
      write('a/application.properties', 'v=a');
      write('b/application-dev.properties', 'v=b-dev');
      write('a/application-dev.properties', 'w=a-dev');
      write('b/application.properties', 'w=b');
      // One group: a profile file beats every non-profile file.
      final one = env({
        'spring.config.location': 'file:$root/b/;file:$root/a/',
        'spring.profiles.active': 'dev',
      });
      process(one);
      expect(one.getProperty('v'), 'b-dev');
      expect(one.getProperty('w'), 'a-dev');
      // Two groups: the later group wins entirely.
      final two = env({
        'spring.config.location': 'file:$root/b/,file:$root/a/',
        'spring.profiles.active': 'dev',
      });
      process(two);
      expect(two.getProperty('v'), 'a');
      expect(two.getProperty('w'), 'a-dev');
      // additional-location groups come after (and win over) the others.
      final more = env({
        'spring.config.additional-location': 'file:$root/b/',
        'spring.profiles.active': 'dev',
      });
      process(more, locations: ['file:$root/a/']);
      expect(more.getProperty('v'), 'b-dev');
      expect(more.getProperty('w'), 'b');
    });

    test('config/*/ searches every subdirectory in alphabetical order', () {
      write('config/b/application.properties', 'v=b');
      write('config/a/application.properties', 'v=a\nonlyA=1');
      write('config/a/application-dev.yml', 'dev: a');
      write('config/..data/application.properties', 'v=hidden\nhidden=1');
      write('config/application.properties', 'v=config\nbase=1');
      final e = env({'spring.profiles.active': 'dev'});
      process(e);
      expect(e.getProperty('v'), 'b', reason: 'later directories win');
      expect(e.getProperty('onlyA'), '1');
      expect(e.getProperty('base'), '1');
      expect(e.getProperty('dev'), 'a');
      expect(e.getProperty('hidden'), isNull);
    });

    test('wildcard file locations and invalid wildcards', () {
      write('etc/b/app.properties', 'v=b');
      write('etc/a/app.properties', 'v=a');
      final e = env({
        'spring.config.location': 'file:$root/etc/*/app.properties',
      });
      process(e);
      expect(e.getProperty('v'), 'b');
      for (final location in [
        'optional:classpath:/config/*/',
        'optional:file:$root/*/*/',
        'optional:file:$root/config/*.properties',
      ]) {
        expect(
          () => process(env({'spring.config.location': location})),
          throwsA(isA<ConfigDataLoadException>()),
          reason: location,
        );
      }
    });
  });

  group('environment after processing', () {
    test('relaxed names over config files and the OS environment', () {
      write('application.yml', 'app:\n  readTimeout: 5s\n  max_size: 10\n');
      final e = StandardEnvironment(
        systemEnvironment: {'APP_LOGGERLEVEL': 'full', 'APP_MAXSIZE': '20'},
      );
      process(e);
      expect(e.getProperty('app.read-timeout'), '5s');
      expect(e.getProperty('app.logger-level'), 'full');
      // The OS environment is above the config files: precedence decides.
      expect(e.getProperty('app.max-size'), '20');
      expect(
        e.resolveRequiredPlaceholders(
          r'${app.read-timeout}/${app.logger-level}',
        ),
        '5s/full',
      );
    });
  });
}
