import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

// Spring Boot 4 config data behaviour: profile groups, location errors,
// `spring.config.on-not-found`, extension hints and `configtree:` imports.
void main() {
  late Directory temp;
  late String root;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('scd_config_parity_');
    root = temp.path.replaceAll(r'\', '/');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  void write(String path, String content) => File('$root/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  StandardEnvironment env([Map<String, Object?> props = const {}]) =>
      StandardEnvironment(systemEnvironment: {})
        ..propertySources.addFirst(MapPropertySource('cli', props));

  void process(StandardEnvironment environment) => ConfigDataEnvironment(
    environment,
    defaultLocations: ['optional:file:$root/'],
  ).processAndApplySync();

  group('profile groups expand depth-first (Boot Profiles.expandProfiles)', () {
    test('a listed member moves behind its group', () {
      write(
        'application.properties',
        'spring.profiles.active=prod,db\n'
            'spring.profiles.group.prod=db,cache\n',
      );
      final e = env();
      process(e);
      expect(e.activeProfiles, ['prod', 'db', 'cache']);
    });

    test('nested groups follow their member', () {
      write(
        'application.properties',
        'spring.profiles.active=a,d\n'
            'spring.profiles.group.a=b,c\n'
            'spring.profiles.group.b=d,e\n',
      );
      final e = env();
      process(e);
      expect(e.activeProfiles, ['a', 'b', 'd', 'e', 'c']);
    });
  });

  test('a directory location without a trailing / gets Boot\'s message', () {
    Directory('$root/conf').createSync();
    expect(
      () => process(env({'spring.config.location': 'file:$root/conf'})),
      throwsA(
        isA<ConfigDataLoadException>().having(
          (e) => e.message,
          'message',
          "File extension is not known to any PropertySourceLoader. If the "
              "location is meant to reference a directory, it must end in '/'",
        ),
      ),
    );
  });

  group('spring.config.on-not-found', () {
    test('ignore skips missing files, directories and imports', () {
      write(
        'application.properties',
        'spring.config.import=file:$root/missing.properties\nname=app',
      );
      final e = env({
        'spring.config.on-not-found': 'ignore',
        'spring.config.additional-location':
            'file:$root/nope.properties,file:$root/nodir/',
      });
      process(e);
      expect(e.getProperty('name'), 'app');
    });

    test('fail (the default) reports the missing location', () {
      expect(
        () => process(
          env({'spring.config.import': 'file:$root/missing.properties'}),
        ),
        throwsA(isA<ConfigDataResourceNotFoundException>()),
      );
    });

    test('other values are rejected', () {
      expect(
        () => process(env({'spring.config.on-not-found': 'skip'})),
        throwsA(isA<ConfigDataLoadException>()),
      );
    });
  });

  test('an extension hint loads a file without extension', () {
    write('conf', 'hinted=yes\nshared=base');
    write('conf-dev', 'shared=dev');
    final e = env({
      'spring.config.import': 'file:$root/conf[.properties]',
      'spring.profiles.active': 'dev',
    });
    process(e);
    expect(e.getProperty('hinted'), 'yes');
    expect(e.getProperty('shared'), 'dev');
  });

  group('configtree:', () {
    test('every file is a property named by its path', () {
      write('tree/db/username', 'admin\n');
      write('tree/db/password', 'secret');
      write('tree/..data/ignored', 'x');
      write('tree/..hidden', 'x');
      final e = env({'spring.config.import': 'configtree:$root/tree/'});
      process(e);
      expect(e.getProperty('db.username'), 'admin');
      expect(e.getProperty('db.password'), 'secret');
      expect(e.containsProperty('..hidden'), isFalse);
      expect(
        e.propertySources.map((s) => s.name),
        contains("Config tree '$root/tree/'"),
      );
    });

    test('a wildcard reads each subdirectory', () {
      write('mounts/a/one', '1');
      write('mounts/b/two', '2');
      final e = env({'spring.config.import': 'configtree:$root/mounts/*/'});
      process(e);
      expect(e.getProperty('one'), '1');
      expect(e.getProperty('two'), '2');
    });

    test('a missing tree fails unless optional', () {
      expect(
        () => process(env({'spring.config.import': 'configtree:$root/no/'})),
        throwsA(isA<ConfigDataResourceNotFoundException>()),
      );
      final e = env({'spring.config.import': 'optional:configtree:$root/no/'});
      process(e);
    });
  });

  test('`a..b` and `a.[0]` are not valid property names', () {
    expect(ConfigurationPropertyName.isValid('a..b'), isFalse);
    expect(ConfigurationPropertyName.isValid('a.[0]'), isFalse);
    expect(ConfigurationPropertyName.isValid('a[0].b'), isTrue);
    expect(ConfigurationPropertyName.isValid('a[0][1]'), isTrue);
    expect(
      () => ConfigurationPropertyName.of('a..b'),
      throwsA(isA<InvalidConfigurationPropertyNameException>()),
    );
  });
}
