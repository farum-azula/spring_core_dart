import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_core_dart/core.dart';
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

/// Minimal "key: value" loader standing in for a YAML loader.
class _ColonLoader implements PropertySourceLoader {
  @override
  List<String> get fileExtensions => const ['yml', 'yaml'];

  @override
  List<AbstractPropertySource<Object>> load(String name, String content) => [
    MapPropertySource(name, {
      for (final line in const LineSplitter().convert(content))
        if (line.contains(':'))
          line.substring(0, line.indexOf(':')).trim(): line
              .substring(line.indexOf(':') + 1)
              .trim(),
    }),
  ];
}

void main() {
  late Directory temp;
  late String root;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('scd_config_');
    root = temp.path;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  void write(String path, String content) => File('$root/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  StandardEnvironment env([Map<String, Object?> props = const {}]) =>
      StandardEnvironment(systemEnvironment: {})
        ..propertySources.addFirst(MapPropertySource('cli', props));

  ConfigDataEnvironment config(
    StandardEnvironment environment, {
    List<PropertySourceLoader>? loaders,
    ResourceLoader? resourceLoader,
  }) => ConfigDataEnvironment(
    environment,
    defaultLocations: ['optional:file:$root/', 'optional:file:$root/config/'],
    resourceLoader: resourceLoader,
    loaders: loaders ?? const [PropertiesPropertySourceLoader()],
  );

  group('review fixes', () {
    test('a negated on-profile document is not applied when the profile is '
        'active', () {
      write('application.properties', '''
level=INFO
#---
spring.config.activate.on-profile=!prod
level=DEBUG
''');
      final prod = env({'spring.profiles.active': 'prod'});
      config(prod).processAndApplySync();
      expect(prod.getProperty('level'), 'INFO');

      final dev = env({'spring.profiles.active': 'dev'});
      config(dev).processAndApplySync();
      expect(dev.getProperty('level'), 'DEBUG');
    });

    test('a guard may use a property defined in a later document', () {
      write('application.properties', '''
#---
spring.config.activate.on-profile=\${target}
mode=targeted
#---
target=dev
''');
      final e = env({'spring.profiles.active': 'dev'});
      config(e).processAndApplySync();
      expect(e.getProperty('mode'), 'targeted');
    });

    test('a relative import cycle terminates', () {
      write('application.properties', '''
spring.config.import=./application.properties,config/a.properties
base=1
''');
      write('config/a.properties', '''
spring.config.import=../config/a.properties
a=2
''');
      final e = env();
      config(e).processAndApplySync();
      expect(e.getProperty('base'), '1');
      expect(e.getProperty('a'), '2');
    });
  });

  test('no files: nothing changes', () {
    final e = env();
    config(e).processAndApplySync();
    expect(e.propertySources.map((s) => s.name), ['cli', 'systemEnvironment']);
    expect(e.activeProfiles, isEmpty);
  });

  test('default locations of the real constructor are optional', () {
    final e = env();
    ConfigDataEnvironment(e).processAndApplySync();
    expect(ConfigDataEnvironment.defaultSearchLocations, [
      'optional:classpath:/',
      'optional:classpath:/config/',
      'optional:file:./',
      'optional:file:./config/',
    ]);
  });

  test('precedence: config/ over ./, profile files over all base files', () {
    write('application.properties', 'a=root\nb=root\nc=root\nd=root');
    write('config/application.properties', 'a=config\nb=config');
    write('application-dev.properties', 'a=root-dev\nc=root-dev');
    write('config/application-dev.properties', 'a=config-dev');
    final e = env({'spring.profiles.active': 'dev'});
    config(e).processAndApplySync();
    expect(e.getProperty('a'), 'config-dev');
    expect(e.getProperty('b'), 'config');
    expect(e.getProperty('c'), 'root-dev');
    expect(e.getProperty('d'), 'root');
    expect(e.activeProfiles, ['dev']);
    expect(e.propertySources.first.name, 'cli');
    expect(
      e.propertySources.elementAt(2).name,
      "Config resource 'file:$root/config/application-dev.properties'",
    );
  });

  test('higher sources win over config files', () {
    write('application.properties', 'server.port=8080\nx=file');
    final e = env({'server.port': '9000'});
    config(e).processAndApplySync();
    expect(e.getPropertyAs<int>('server.port'), 9000);
    expect(e.getProperty('x'), 'file');
  });

  test('profiles activated from a config file', () {
    write('application.properties', 'spring.profiles.active=dev,eu\nname=base');
    write('application-dev.properties', 'name=dev');
    write('application-eu.properties', 'name=eu\nregion=eu');
    final e = env();
    config(e).processAndApplySync();
    expect(e.activeProfiles, ['dev', 'eu']);
    expect(e.getProperty('name'), 'eu', reason: 'last profile wins');
    expect(e.getProperty('region'), 'eu');
  });

  test('programmatic profiles win over the file property', () {
    write('application.properties', 'spring.profiles.active=dev');
    write('application-prod.properties', 'name=prod');
    write('application-dev.properties', 'name=dev');
    final e = env()..setActiveProfiles(['prod']);
    config(e).processAndApplySync();
    expect(e.activeProfiles, ['prod']);
    expect(e.getProperty('name'), 'prod');
  });

  test('include and groups', () {
    write(
      'application.properties',
      'spring.profiles.active=prod\n'
          'spring.profiles.include=metrics\n'
          'spring.profiles.group.prod=db,cache\n'
          'spring.profiles.group.db=pool',
    );
    write('application-pool.properties', 'pool=yes');
    final e = env();
    config(e).processAndApplySync();
    expect(e.activeProfiles, ['prod', 'db', 'pool', 'cache', 'metrics']);
    expect(e.getProperty('pool'), 'yes');
  });

  test('include alone activates profiles; includes merge across files', () {
    write('application.properties', 'spring.profiles.include=a');
    write('config/application.properties', 'spring.profiles.include=b,a');
    final e = env();
    config(e).processAndApplySync();
    expect(e.activeProfiles, ['a', 'b']);
  });

  test('default profile file when no profile is active', () {
    write('application-default.properties', 'mode=default');
    final e = env();
    config(e).processAndApplySync();
    expect(e.getProperty('mode'), 'default');
    expect(e.activeProfiles, isEmpty);
  });

  test('multi-document files with on-profile', () {
    write(
      'application.properties',
      'name=base\n'
          'color=blue\n'
          '#---\n'
          'spring.config.activate.on-profile=dev\n'
          'name=dev-doc\n'
          '!---\n'
          'spring.config.activate.on-profile=prod | staging\n'
          'name=prod-doc\n'
          '#---\n'
          '#---\n'
          'spring.config.activate.on-profile=default\n'
          'color=default-color\n',
    );
    final dev = env({'spring.profiles.active': 'dev'});
    config(dev).processAndApplySync();
    expect(dev.getProperty('name'), 'dev-doc');
    expect(dev.getProperty('color'), 'blue');

    final staging = env({'spring.profiles.active': 'staging'});
    config(staging).processAndApplySync();
    expect(staging.getProperty('name'), 'prod-doc');

    final none = env();
    config(none).processAndApplySync();
    expect(none.getProperty('name'), 'base');
    expect(none.getProperty('color'), 'default-color');
  });

  test('imports: relative, absolute, optional, placeholders, cycles', () {
    write(
      'application.properties',
      'name=app\n'
          'dir=$root/extra\n'
          'spring.config.import=more.properties,'
          r'file:${dir}/abs.properties,optional:missing.properties',
    );
    write(
      'more.properties',
      'name=imported\nspring.config.import=application.properties',
    );
    write('extra/abs.properties', 'abs=yes');
    final e = env();
    config(e).processAndApplySync();
    expect(e.getProperty('name'), 'imported', reason: 'imports override');
    expect(e.getProperty('abs'), 'yes');
  });

  test('on-profile guards resolve placeholders', () {
    write(
      'application.properties',
      'target.profile=dev\n'
          '#---\n'
          'spring.config.activate.on-profile=\${target.profile}\n'
          'x=dev-doc\n'
          '#---\n'
          'spring.config.activate.on-profile=\${target.profile}-other\n'
          'y=other-doc',
    );
    final e = env({'spring.profiles.active': 'dev'});
    config(e).processAndApplySync();
    expect(e.getProperty('x'), 'dev-doc');
    expect(e.getProperty('y'), isNull);
  });

  test('Windows drive and backslash imports are absolute', () {
    for (final location in [r'C:\cfg\x.properties', 'D:/cfg/x.properties']) {
      // Backslashes are escapes in .properties files.
      final escaped = location.replaceAll(r'\', r'\\');
      write('application.properties', 'spring.config.import=$escaped');
      expect(
        () => config(env()).processAndApplySync(),
        throwsA(
          isA<ConfigDataResourceNotFoundException>().having(
            (e) => e.location,
            'location',
            location,
          ),
        ),
      );
    }
  });

  test('missing non-optional import fails', () {
    write('application.properties', 'spring.config.import=nope.properties');
    expect(
      () => config(env()).processAndApplySync(),
      throwsA(
        isA<ConfigDataResourceNotFoundException>().having(
          (e) => e.toString(),
          'text',
          contains("Prefix the location with 'optional:'"),
        ),
      ),
    );
  });

  test('spring.config.name, location and additional-location', () {
    write('custom/app.properties', 'from=custom');
    write('custom/app-dev.properties', 'dev=yes');
    write('more/app.properties', 'from=more');
    write('single.properties', 'single=yes');
    write('single-dev.properties', 'singleDev=yes');
    final e = env({
      'spring.config.name': 'app',
      'spring.config.location':
          'file:$root/custom/,file:$root/single.properties',
      'spring.config.additional-location': 'optional:file:$root/more/',
      'spring.profiles.active': 'dev',
    });
    config(e).processAndApplySync();
    expect(e.getProperty('from'), 'more');
    expect(e.getProperty('dev'), 'yes');
    expect(e.getProperty('single'), 'yes');
    expect(e.getProperty('singleDev'), 'yes');
  });

  test('explicit locations without extension or profile variants', () {
    write('noext', 'x=1');
    final e = env({
      'spring.config.location': 'optional:file:$root/noext',
      'spring.profiles.active': 'dev',
    });
    config(e).processAndApplySync();
    expect(e.getProperty('x'), isNull);
    expect(
      () =>
          config(env({'spring.config.location': 'file:$root/noext'}))
              .processAndApplySync(),
      throwsA(
        isA<ConfigDataLoadException>().having(
          (e) => e.toString(),
          'text',
          contains('no PropertySourceLoader'),
        ),
      ),
    );
    expect(
      () =>
          config(env({'spring.config.location': 'file:$root/none.properties'}))
              .processAndApplySync(),
      throwsA(isA<ConfigDataResourceNotFoundException>()),
    );
  });

  test('profile properties are invalid in profile-specific documents', () {
    write('application-dev.properties', 'spring.profiles.active=prod');
    expect(
      () =>
          config(env({'spring.profiles.active': 'dev'})).processAndApplySync(),
      throwsA(
        isA<InvalidConfigDataPropertyException>()
            .having((e) => e.property, 'property', 'spring.profiles.active')
            .having((e) => e.toString(), 'text', contains('profile-specific')),
      ),
    );
    write(
      'application.properties',
      'a=1\n#---\nspring.config.activate.on-profile=x\nspring.profiles.group.y=z',
    );
    expect(
      () => config(env({'spring.profiles.active': 'x'})).processAndApplySync(),
      throwsA(isA<InvalidConfigDataPropertyException>()),
    );
  });

  test('custom loaders (e.g. YAML) are picked by extension', () {
    write('application.yml', 'name: from-yml\nonly: yml');
    write('application.properties', 'name=from-properties');
    final e = env();
    config(
      e,
      loaders: [const PropertiesPropertySourceLoader(), _ColonLoader()],
    ).processAndApplySync();
    expect(e.getProperty('name'), 'from-yml', reason: 'later loader wins');
    expect(e.getProperty('only'), 'yml');
  });

  group('async-only resources', () {
    ResourceLoader assets(Map<String, String> files) => DefaultResourceLoader(
      protocolResolvers: [
        FunctionProtocolResolver(
          (location, _) => location.startsWith('asset:')
              ? _AsyncResource(location, files[location.substring(6)])
              : null,
        ),
      ],
    );

    test('processAndApply reads them', () async {
      final e = env({'spring.config.location': 'asset:config/'});
      await config(
        e,
        resourceLoader: assets({
          'config/application.properties': 'spring.profiles.active=dev\nspring.config.import=extra.properties',
          'config/application-dev.properties': 'mode=dev',
          'config/extra.properties': 'extra=1',
        }),
      ).processAndApply();
      expect(e.getProperty('mode'), 'dev');
      expect(e.getProperty('extra'), '1');
    });

    test('processAndApplySync rejects them', () {
      final e = env({'spring.config.location': 'asset:config/'});
      expect(
        () => config(
          e,
          resourceLoader: assets({'config/application.properties': 'a=1'}),
        ).processAndApplySync(),
        throwsA(
          isA<ConfigDataLoadException>().having(
            (e) => e.toString(),
            'text',
            contains('processAndApply()'),
          ),
        ),
      );
    });

    test('imports relative to a scheme-only location', () async {
      final e = env({'spring.config.location': 'asset:application.properties'});
      await config(
        e,
        resourceLoader: assets({
          'application.properties': 'spring.config.import=b.properties',
          'b.properties': 'b=1',
        }),
      ).processAndApply();
      expect(e.getProperty('b'), '1');
    });
  });

  test('placeholders across files resolve lazily', () {
    write('application.properties', r'greeting=Hello ${name}');
    write('config/application.properties', 'name=NEON');
    final e = env();
    config(e).processAndApplySync();
    expect(e.getProperty('greeting'), 'Hello NEON');
  });
}
