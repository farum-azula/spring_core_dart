import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

  test("a directory location without a trailing / gets Boot's message", () {
    Directory('$root/conf').createSync();
    expect(
      () => process(env({'spring.config.location': 'file:$root/conf'})),
      throwsA(
        isA<ConfigDataLoadException>().having(
          (e) => e.message,
          'message',
          'File extension is not known to any PropertySourceLoader. If the '
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

    // The tree used to be read from the disk whatever the loader's `file:`
    // locations were: the Flutter web dev config builder, which reads the
    // config as a browser does, got the build machine's files.
    test('is read from the file system of the resource loader', () {
      write('tree/db/username', 'admin');
      write('mounts/a/one', '1');
      final elsewhere = DefaultResourceLoader(
        protocolResolvers: [InMemoryProtocolResolver('file:', const {})],
      );
      void processWith(StandardEnvironment environment) =>
          ConfigDataEnvironment(
            environment,
            resourceLoader: elsewhere,
            defaultLocations: const [],
          ).processAndApplySync();

      final optional = env({
        'spring.config.import':
            'optional:configtree:$root/tree/,'
            'optional:configtree:$root/mounts/*/',
      });
      processWith(optional);
      expect(optional.containsProperty('db.username'), isFalse);
      expect(optional.containsProperty('one'), isFalse);
      expect(
        () => processWith(
          env({'spring.config.import': 'configtree:$root/tree/'}),
        ),
        throwsA(isA<ConfigDataResourceNotFoundException>()),
      );
    });
  });

  // Boot 4.1.2 fails these (ConfigDataEnvironment.checkMandatoryLocations,
  // "cannot be found"); they used to load nothing without an error.
  group('a required wildcard location that finds nothing fails', () {
    late List<String> locations;

    setUp(() {
      write('filesonly/a', 'x');
      write('afile', 'x');
      write('real/sub/r', 'R');
      locations = [
        'configtree:$root/missing/*/',
        'configtree:$root/filesonly/*/',
        'configtree:$root/afile/*/',
        'file:$root/missing/*/app.yaml',
        'file:$root/real/*/app.yaml',
      ];
    });

    test('with "cannot be found"', () {
      for (final location in locations) {
        expect(
          () => process(env({'spring.config.import': location})),
          throwsA(
            isA<ConfigDataLocationNotFoundException>()
                .having((e) => e.location, 'location', location)
                .having((e) => e.reason, 'reason', isNull),
          ),
          reason: location,
        );
      }
    });

    test('unless optional: or spring.config.on-not-found=ignore', () {
      for (final location in locations) {
        process(env({'spring.config.import': 'optional:$location'}));
        process(
          env({
            'spring.config.import': location,
            'spring.config.on-not-found': 'ignore',
          }),
        );
      }
    });

    test('a match is enough', () {
      write('real/sub/app.yaml', 'found: yes\n');
      final e = env({
        'spring.config.import':
            'file:$root/real/*/app.yaml,configtree:$root/real/*/',
      });
      process(e);
      expect(e.getProperty('found'), 'yes');
      expect(e.getProperty('r'), 'R');
    });
  });

  // Boot 4.1.2 (the fifth review's probes): only the `-{profile}`
  // variants searched by name are skippable (StandardConfigDataReference
  // .isSkippable); an import is required wherever it is written. An import
  // in a profile-specific file (in an on-profile document of one, in the
  // profile variant of an import, in a file one imports) was optional: a
  // missing file or a pattern matching nothing loaded without an error.
  group('an import in a profile-specific file is as required as any other', () {
    // The config files of a directory whose `dev` profile imports
    // [location]: from a profile file, an on-profile document in one, the
    // profile variant of an import, and a file a profile file imports.
    List<Map<String, String>> importing(String location) => [
      {
        'application.yaml': 'a: base\n',
        'application-dev.yaml': 'spring.config.import: "$location"\n',
      },
      {
        'application.yaml': 'a: base\n',
        'application-dev.properties':
            'b=dev\n#---\nspring.config.activate.on-profile=dev\n'
            'spring.config.import=$location\n',
      },
      {
        'application.yaml': 'a: base\nspring.config.import: base.yaml\n',
        'base.yaml': 'base: yes\n',
        'base-dev.yaml': 'spring.config.import: "$location"\n',
      },
      {
        'application-dev.yaml': 'spring.config.import: extra.yaml\n',
        'extra.yaml': 'spring.config.import: "$location"\n',
      },
    ];

    late List<(String, TypeMatcher<Exception>)> missing;

    setUp(() {
      write('real/sub/r', 'R');
      missing = [
        (
          'file:$root/missing.yaml',
          isA<ConfigDataResourceNotFoundException>(),
        ),
        (
          'file:$root/real/*/x.yaml',
          isA<ConfigDataLocationNotFoundException>(),
        ),
        ('file:$root/nodir/', isA<ConfigDataLocationNotFoundException>()),
        (
          'configtree:$root/nodir/',
          isA<ConfigDataResourceNotFoundException>(),
        ),
        (
          'configtree:$root/nodir/*/',
          isA<ConfigDataLocationNotFoundException>(),
        ),
      ];
    });

    test('a missing one fails the start', () {
      var i = 0;
      for (final (location, matcher) in missing) {
        for (final files in importing(location)) {
          final directory = 'case${i++}';
          files.forEach((name, content) => write('$directory/$name', content));
          expect(
            () => ConfigDataEnvironment(
              env({'spring.profiles.active': 'dev'}),
              defaultLocations: ['optional:file:$root/$directory/'],
            ).processAndApplySync(),
            throwsA(matcher.having((e) => '$e', 'message', contains(location))),
            reason: '$location: $files',
          );
        }
      }
    });

    test('unless optional:, spring.config.on-not-found=ignore or inactive; '
        'the profile variants of its imports may be missing', () {
      write('empty/.keep', '');
      write('extra.yaml', 'extra: yes\n');
      for (final (location, _) in missing) {
        write(
          'optional/application-dev.yaml',
          'spring.config.import:\n'
              '  - "optional:$location"\n'
              '  - file:$root/empty/\n'
              '  - ../extra.yaml\n'
              '---\n'
              'spring.config.activate.on-profile: prod\n'
              'spring.config.import: "$location"\n',
        );
        final e = env({'spring.profiles.active': 'dev'});
        ConfigDataEnvironment(
          e,
          defaultLocations: ['optional:file:$root/optional/'],
        ).processAndApplySync();
        expect(e.getProperty('extra'), 'yes', reason: location);
        write(
          'ignore/application-dev.yaml',
          'spring.config.import: "$location"\n',
        );
        ConfigDataEnvironment(
          env({
            'spring.profiles.active': 'dev',
            'spring.config.on-not-found': 'ignore',
          }),
          defaultLocations: ['optional:file:$root/ignore/'],
        ).processAndApplySync();
      }
    });
  });

  // Writes [files] into a new directory and reads it as the only config
  // location, with [props] on the command line.
  var cases = 0;
  StandardEnvironment load(
    Map<String, String> files, [
    Map<String, Object?> props = const {},
  ]) {
    final directory = 'load${cases++}';
    files.forEach((name, content) => write('$directory/$name', content));
    final e = env(props);
    ConfigDataEnvironment(
      e,
      defaultLocations: ['optional:file:$root/$directory/'],
    ).processAndApplySync();
    return e;
  }

  // Boot 4.1.2 decides "cannot be found" after the profile phase
  // (ConfigDataEnvironment.checkMandatoryLocations): a required location
  // is found when any of its resources was loaded, its profile variants
  // included. A wildcard file location that only a profile variant
  // matched failed here before the profiles were known (the sixth review's
  // q7; Boot: a=base b=dev).
  group('a location is found when its profile variants find a file', () {
    late String location;

    setUp(() {
      write('conf/a/app-dev.yaml', 'b: dev\n');
      write('conf/a/app-default.yaml', 'b: default\n');
      location = 'file:$root/conf/*/app.yaml';
    });

    test('a wildcard file location, wherever it is written', () {
      const dev = {'spring.profiles.active': 'dev'};
      final imports = 'spring.config.import: "$location"\n';
      for (final (files, props, b) in [
        ({'application.yaml': 'a: base\n$imports'}, dev, 'dev'),
        (
          const {'application.yaml': 'a: base\n'},
          {
            ...dev,
            'spring.config.import': location,
          },
          'dev',
        ),
        (
          {'application.yaml': 'spring.profiles.active: dev\n$imports'},
          const <String, Object?>{},
          'dev',
        ),
        ({'application.yaml': imports}, const <String, Object?>{}, 'default'),
        ({'application-dev.yaml': imports}, dev, 'dev'),
        (
          {
            'application.yaml':
                'a: base\n---\nspring.config.activate.on-profile: dev\n'
                '$imports',
          },
          dev,
          'dev',
        ),
      ]) {
        expect(load(files, props).getProperty('b'), b, reason: '$files');
      }
    });

    test('without a matching profile it still fails; a missing file is not '
        'rescued by its variant', () {
      expect(
        () => load(
          {'application.yaml': 'spring.config.import: "$location"\n'},
          {'spring.profiles.active': 'prod'},
        ),
        throwsA(
          isA<ConfigDataLocationNotFoundException>()
              .having((e) => e.location, 'location', location)
              .having((e) => e.reason, 'reason', isNull),
        ),
      );
      // Boot: the plain file is resolved first and fails at once.
      write('single/app-dev.yaml', 'b: dev\n');
      expect(
        () => load(
          {
            'application.yaml':
                'spring.config.import: file:$root/single/app.yaml\n',
          },
          {'spring.profiles.active': 'dev'},
        ),
        throwsA(isA<ConfigDataResourceNotFoundException>()),
      );
    });

    // Boot never counts a classpath directory as existing (its
    // resolveNonPatternEmptyDirectories); one read from disk did here.
    test('a classpath directory counts only when a file is found in it', () {
      write('cp/cpdir/application-dev.yaml', 'b: cp\n');
      final remove = ClasspathResources.addDirectory('$root/cp');
      try {
        final e = env({
          'spring.config.import': 'classpath:/cpdir/',
          'spring.profiles.active': 'dev',
        });
        process(e);
        expect(e.getProperty('b'), 'cp');
        expect(
          () => process(env({'spring.config.import': 'classpath:/cpdir/'})),
          throwsA(
            isA<ConfigDataLocationNotFoundException>().having(
              (e) => e.location,
              'location',
              'classpath:/cpdir/',
            ),
          ),
        );
      } finally {
        remove();
      }
    });

    // Boot: a `;` group is one ConfigDataLocation, optional when its first
    // entry is; a missing directory in it failed here although another
    // entry was found.
    test('a ; group is one location, found when any entry finds something', () {
      write('g/application.yaml', 'a: g\n');
      for (final group in [
        'file:$root/g/;file:$root/g/nodir/',
        'file:$root/g/nodir/;optional:file:$root/g/',
        'optional:file:$root/g/;file:$root/g/missing.yaml',
      ]) {
        final e = env({'spring.config.location': group});
        process(e);
        expect(e.getProperty('a'), 'g', reason: group);
      }
      final none = 'file:$root/g/nodir1/;file:$root/g/nodir2/';
      expect(
        () => process(env({'spring.config.location': none})),
        throwsA(
          isA<ConfigDataLocationNotFoundException>().having(
            (e) => e.location,
            'location',
            none,
          ),
        ),
      );
      expect(
        () => process(
          env({
            'spring.config.location': 'file:$root/g/;file:$root/g/missing.yaml',
          }),
        ),
        throwsA(isA<ConfigDataResourceNotFoundException>()),
      );
    });
  });

  // Boot resolves every spring.config.import value as a ConfigDataLocation
  // split at `;` (StandardConfigDataLocationResolver.resolve), in a file
  // too; only the initial locations were split here, so a file's
  // `x.yaml;y.yaml` was one file name (the sixth review's E4, E5, D3f;
  // checked against Boot 4.1.2).
  group("a ; group in a file's spring.config.import is one location", () {
    test('its entries load, each optional or not', () {
      for (final (import, b, c) in [
        ('x.yaml;y.yaml', 'x', 'y'),
        ('optional:nodir/;x.yaml', 'x', null),
        ('x.yaml;optional:nodir/', 'x', null),
        // A missing entry of an optional group is skipped.
        ('optional:x.yaml;missing.yaml', 'x', null),
        ('optional:x.yaml;nodir/', 'x', null),
      ]) {
        final e = load({
          'application.yaml': 'a: base\nspring.config.import: "$import"\n',
          'x.yaml': 'b: x\n',
          'y.yaml': 'c: y\n',
        });
        expect(e.getProperty('a'), 'base', reason: import);
        expect(e.getProperty('b'), b, reason: import);
        expect(e.getProperty('c'), c, reason: import);
      }
    });

    test('in a list, in .properties, relative to the importing file, with '
        'profile variants', () {
      final e = load(
        {
          'application.properties':
              'spring.config.import=sub/x.yaml;y.yaml,optional:nodir/;z.yaml\n',
          'sub/x.yaml': 'b: x\nspring.config.import: "w.yaml;v.yaml"\n',
          'sub/w.yaml': 'w: w\n',
          'sub/v.yaml': 'v: v\n',
          'y.yaml': 'c: y\n',
          'y-dev.yaml': 'c: ydev\n',
          'z.yaml': 'z: z\n',
        },
        {'spring.profiles.active': 'dev'},
      );
      expect(
        [
          for (final k in ['b', 'c', 'w', 'v', 'z']) e.getProperty(k),
        ],
        ['x', 'ydev', 'w', 'v', 'z'],
      );
      final list = load({
        'application.yaml':
            'spring:\n  config:\n    import:\n'
            '      - "x.yaml;y.yaml"\n      - "optional:nodir/;z.yaml"\n',
        'x.yaml': 'b: x\n',
        'y.yaml': 'c: y\n',
        'z.yaml': 'z: z\n',
      });
      expect(
        [
          for (final k in ['b', 'c', 'z']) list.getProperty(k),
        ],
        ['x', 'y', 'z'],
      );
    });

    test('a missing required entry fails, and the error names the group as '
        'written', () {
      for (final (import, matcher) in [
        ('x.yaml;missing.yaml', isA<ConfigDataResourceNotFoundException>()),
        ('nodir/;optional:x2.yaml', isA<ConfigDataLocationNotFoundException>()),
        ('nodir1/;nodir2/', isA<ConfigDataLocationNotFoundException>()),
      ]) {
        expect(
          () => load({
            'application.yaml': 'a: base\nspring.config.import: "$import"\n',
            'x.yaml': 'b: x\n',
          }),
          throwsA(
            matcher.having((e) => (e as dynamic).location, 'location', import),
          ),
          reason: import,
        );
      }
    });
  });

  // Boot names the location as written (ConfigDataResourceNotFoundException
  // .withLocation, ConfigDataLocationNotFoundException): a relative import
  // as it is, an extension hint kept, a `;` group whole. The resolved path
  // was given (`file:…/x` for `x[.yml]`), and the web dev config builder's
  // advice to prefix it with `optional:` then named a location that loads
  // nothing.
  test('a location that is not found is named as written', () {
    for (final (import, matcher) in [
      ('x[.yml]', isA<ConfigDataResourceNotFoundException>()),
      ('missing.yaml', isA<ConfigDataResourceNotFoundException>()),
      ('nodir/', isA<ConfigDataLocationNotFoundException>()),
      ('sub/../nodir/', isA<ConfigDataLocationNotFoundException>()),
    ]) {
      expect(
        () => load({'application.yaml': 'spring.config.import: "$import"\n'}),
        throwsA(
          matcher
              .having((e) => (e as dynamic).location, 'location', import)
              .having(
                (e) => '$e',
                'message',
                contains("location '$import'"),
              ),
        ),
        reason: import,
      );
    }
    final group = 'file:$root/;file:$root/missing.yaml';
    expect(
      () => process(env({'spring.config.location': group})),
      throwsA(
        isA<ConfigDataResourceNotFoundException>()
            .having((e) => e.location, 'location', group)
            .having(
              (e) => e.description,
              'description',
              'file [$root/missing.yaml]',
            ),
      ),
    );
  });

  // Boot finds the profile keys of a `-{profile}` file by its relaxed
  // names (ConfigurationPropertySource.getConfigurationProperty): they
  // were checked by their exact names only, so `spring.profiles.Active`
  // was ignored (the sixth review's K4; checked against Boot 4.1.2).
  group('profile keys are found under any relaxed spelling', () {
    test('in a profile file, in any of its documents', () {
      for (final (file, property) in [
        (
          'application-dev.properties',
          ('b=dev\nspring.profiles.Active=x\n', 'spring.profiles.active'),
        ),
        (
          'application-dev.yaml',
          (
            'b: dev\nspring:\n  profiles:\n    ACTIVE: x\n',
            'spring.profiles.active',
          ),
        ),
        (
          'application-dev.properties',
          ('spring.Profiles.Include[0]=x\n', 'spring.profiles.include[0]'),
        ),
        (
          'application-dev.properties',
          ('spring.profiles.de-fault=x\n', 'spring.profiles.default'),
        ),
        (
          'application-dev.yaml',
          (
            'b: dev\n---\nspring.config.activate.on-profile: prod\n'
                'spring.profiles.Include: x\n',
            'spring.profiles.include',
          ),
        ),
      ]) {
        expect(
          () => load(
            {'application.yaml': 'a: base\n', file: property.$1},
            {'spring.profiles.active': 'dev'},
          ),
          throwsA(
            isA<InvalidConfigDataPropertyException>().having(
              (e) => e.property,
              'property',
              property.$2,
            ),
          ),
          reason: property.$1,
        );
      }
      // Only environment variables spell a name this way, as in Boot.
      final e = load(
        {
          'application.yaml': 'a: base\n',
          'application-dev.properties': 'b=dev\nSPRING_PROFILES_ACTIVE=x\n',
        },
        {'spring.profiles.active': 'dev'},
      );
      expect(e.getProperty('b'), 'dev');
      expect(e.activeProfiles, ['dev']);
    });

    test('the legacy spring.profiles, and in an on-profile document read '
        'while the profiles are decided', () {
      for (final (content, property) in [
        ('a=base\nspring.Profiles=dev\n', 'spring.profiles'),
        ('a=base\nspring.PROFILES[0]=dev\n', 'spring.profiles[0]'),
        (
          'a=base\n#---\nspring.config.activate.on-profile=dev\n'
              'spring.profiles.Active=x\n',
          'spring.profiles.active',
        ),
        (
          'a=base\n#---\nspring.config.activate.on-profile=dev\n'
              'spring.profiles.Group.Dev=x\n',
          'spring.profiles.group.dev',
        ),
      ]) {
        expect(
          () => load(
            {'application.properties': content},
            {'spring.profiles.active': 'dev'},
          ),
          throwsA(
            isA<InvalidConfigDataPropertyException>().having(
              (e) => e.property,
              'property',
              property,
            ),
          ),
          reason: content,
        );
      }
    });
  });

  // Boot 4.1.2 reads the profiles once, before the profile files; files
  // read later cannot change them, and only the `-{profile}` variants
  // themselves are checked (InvalidConfigDataPropertyException
  // .throwIfPropertyFound, isFromProfileSpecificImport). A file imported by
  // a profile file that set `spring.profiles.active` failed here (the
  // sixth review's q14; Boot: a=base b=dev, profiles [dev]).
  group('profile keys of files read after the profiles are decided', () {
    const settings = [
      'spring.profiles.active: other',
      'spring.profiles.include: other',
      'spring.profiles.default: other',
      'spring.profiles.group.dev: other',
    ];

    test('are ignored', () {
      for (final setting in settings) {
        final x = 'c: x\n$setting\n';
        const onDev = 'spring.config.activate.on-profile: dev\n';
        for (final files in [
          // Imported by a profile file.
          {
            'application-dev.yaml': 'spring.config.import: x.yaml\n',
            'x.yaml': x,
          },
          // Imported by an on-profile document.
          {
            'application.yaml': '---\n${onDev}spring.config.import: x.yaml\n',
            'x.yaml': x,
          },
          // Imported by the profile variant of an import.
          {
            'application.yaml': 'spring.config.import: y.yaml\n',
            'y.yaml': '',
            'y-dev.yaml': 'spring.config.import: x.yaml\n',
            'x.yaml': x,
          },
          // Imported by a file a profile file imports.
          {
            'application-dev.yaml': 'spring.config.import: y.yaml\n',
            'y.yaml': 'spring.config.import: x.yaml\n',
            'x.yaml': x,
          },
          // An on-profile document of a file a profile file imports.
          {
            'application-dev.yaml': 'spring.config.import: x.yaml\n',
            'x.yaml': 'c: x\n---\n$onDev$setting\n',
          },
          // An on-profile document of a file an on-profile document
          // imports.
          {
            'application.yaml': '---\n${onDev}spring.config.import: x.yaml\n',
            'x.yaml': 'c: x\n---\n$onDev$setting\n',
          },
        ]) {
          final e = load(files, {'spring.profiles.active': 'dev'});
          expect(e.getProperty('c'), 'x', reason: '$files');
          expect(e.activeProfiles, ['dev'], reason: '$files');
          expect(e.defaultProfiles, ['default'], reason: '$files');
        }
      }
    });

    test('stay visible, but never activate a profile when none is active', () {
      // Profiles from a file: Boot keeps the imported value readable.
      final e = load({
        'application.yaml': 'spring.profiles.active: dev\n',
        'application-dev.yaml': 'spring.config.import: x.yaml\n',
        'x.yaml': 'c: x\nspring.profiles.active: other\n',
      });
      expect(e.activeProfiles, ['dev']);
      expect(e.getProperty('spring.profiles.active'), 'other');
      // No profile active: the default profile's file and an on-profile
      // `default` document import files that set profiles.
      for (final files in [
        {
          'application-default.yaml': 'spring.config.import: x.yaml\n',
          'x.yaml':
              'c: x\nspring.profiles.active: other\n'
              'spring.profiles.default: other\n',
        },
        {
          'application.yaml':
              '---\nspring.config.activate.on-profile: default\n'
              'spring.config.import: x.yaml\n',
          'x.yaml': 'c: x\nspring.profiles.active: other\n',
        },
      ]) {
        final e = load(files);
        expect(e.getProperty('c'), 'x', reason: '$files');
        expect(e.activeProfiles, isEmpty, reason: '$files');
        expect(e.defaultProfiles, ['default'], reason: '$files');
      }
    });

    test('a profile file may not set active, include or default, in any of '
        'its documents; its groups are ignored', () {
      for (final setting in settings) {
        for (final files in [
          {'application-dev.yaml': 'b: dev\n$setting\n'},
          // The profile variant of an import.
          {
            'application.yaml': 'spring.config.import: x.yaml\n',
            'x.yaml': '',
            'x-dev.yaml': 'b: dev\n$setting\n',
          },
          // A document for another profile.
          {
            'application-dev.yaml':
                'b: dev\n---\nspring.config.activate.on-profile: prod\n'
                '$setting\n',
          },
        ]) {
          StandardEnvironment run() =>
              load(files, {'spring.profiles.active': 'dev'});
          if (setting.startsWith('spring.profiles.group')) {
            final e = run();
            expect(e.getProperty('b'), 'dev', reason: '$files');
            expect(e.activeProfiles, ['dev'], reason: '$files');
          } else {
            expect(
              run,
              throwsA(
                isA<InvalidConfigDataPropertyException>().having(
                  (e) => e.property,
                  'property',
                  setting.substring(0, setting.indexOf(':')),
                ),
              ),
              reason: '$files',
            );
          }
        }
      }
    });
  });

  test("a configtree: location must end with '/', as in Boot", () {
    write('tree/db/username', 'admin');
    for (final location in [
      'configtree:$root/tree/db',
      'optional:configtree:$root/tree/db',
      'configtree:$root/tree/*',
    ]) {
      expect(
        () => process(env({'spring.config.import': location})),
        throwsA(
          isA<ConfigDataLoadException>().having(
            (e) => e.toString(),
            'message',
            contains("Config tree location '"),
          ),
        ),
        reason: location,
      );
    }
  });

  test('configtree:file: with a wildcard reads each subdirectory', () {
    write('mounts/a/one', '1');
    write('mounts/b/two', '2');
    final e = env({'spring.config.import': 'configtree:file:$root/mounts/*/'});
    process(e);
    expect(e.getProperty('one'), '1');
    expect(e.getProperty('two'), '2');
  });

  // Boot's LocationResourceLoader: a wildcard whose base does not exist
  // has no subdirectories (it failed with "wildcard locations must be file
  // system locations" when the loader did not map it to a file).
  test('a wildcard location whose base does not exist has none', () {
    final elsewhere = DefaultResourceLoader(
      protocolResolvers: [InMemoryProtocolResolver('file:', const {})],
    );
    final e = env({
      'spring.config.import': 'optional:file:$root/config/*/',
      'name': 'cli',
    });
    ConfigDataEnvironment(
      e,
      resourceLoader: elsewhere,
      defaultLocations: const [],
    ).processAndApplySync();
    expect(e.getProperty('name'), 'cli');
    expect(
      () => ConfigDataEnvironment(
        env({'spring.config.import': 'file:$root/config/*/'}),
        resourceLoader: elsewhere,
        defaultLocations: const [],
      ).processAndApplySync(),
      throwsA(
        isA<ConfigDataLocationNotFoundException>().having(
          (e) => e.reason,
          'reason',
          'contains no subdirectories',
        ),
      ),
    );
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

  // The seventh review (Boot 4.1.2 runs of each case).
  group('extensions and hints are matched without case, as in Boot', () {
    // Files held in memory are case-sensitive, like a classpath (a jar) or
    // a Linux file system; macOS's usual one is not.
    StandardEnvironment processFiles(
      Map<String, String> files, [
      Map<String, Object?> props = const {},
    ]) {
      final e = env(props);
      ConfigDataEnvironment(
        e,
        resourceLoader: DefaultResourceLoader(
          protocolResolvers: [InMemoryProtocolResolver('memory:', files)],
        ),
        defaultLocations: const ['optional:memory:/'],
      ).processAndApplySync();
      return e;
    }

    // Dart skipped the optional ones silently and failed the required ones
    // ("File extension is not known"); Boot reads them.
    test("an extension: the loader's spelling names the file", () {
      for (final import in ['optional:x.YAML', 'x.YAML', 'x.Yaml']) {
        final e = processFiles(
          {
            'application.properties': 'spring.config.import=$import\n',
            'x.yaml': 'b: x\n',
            'x-dev.yaml': 'c: dev\n',
          },
          {'spring.profiles.active': 'dev'},
        );
        expect(e.getProperty('b'), 'x', reason: import);
        expect(e.getProperty('c'), 'dev', reason: import);
      }
    });

    test('a hint: the file is read as named, in its format', () {
      for (final import in ['optional:x.conf[.YAML]', 'x.conf[.Yml]']) {
        final e = processFiles(
          {
            'application.properties': 'spring.config.import=$import\n',
            'x.conf': 'b: x\n',
            'x.conf-dev': 'c: dev\n',
          },
          {'spring.profiles.active': 'dev'},
        );
        expect(e.getProperty('b'), 'x', reason: import);
        expect(e.getProperty('c'), 'dev', reason: import);
      }
    });

    test('a file spelled x.YAML is not found under that name', () {
      final files = {
        'application.properties': 'spring.config.import=optional:x.YAML\n',
        'x.YAML': 'b: x\n',
      };
      expect(processFiles(files).getProperty('b'), isNull);
      expect(
        () => processFiles({
          ...files,
          'application.properties': 'spring.config.import=x.YAML\n',
        }),
        throwsA(isA<ConfigDataResourceNotFoundException>()),
      );
    });
  });

  // Found with the seventh review: the hint was dropped for a wildcard
  // file, so nothing was read (a required one was "not found").
  test('a wildcard file with an extension hint reads each match', () {
    write('conf/eu/app', 'b: eu\n');
    write('conf/us/app', 'c: us\n');
    final e = env({'spring.config.import': 'file:$root/conf/*/app[.yml]'});
    process(e);
    expect(e.getProperty('b'), 'eu');
    expect(e.getProperty('c'), 'us');
  });

  // Boot binds spring.profiles.group to a map keyed by the names as
  // written; Dart matched them ignoring case, `-` and `_`.
  group('profile group names are matched exactly, as in Boot', () {
    test('another spelling is another group', () {
      for (final (file, active) in [
        ('spring.profiles.group.Prod=dev\n', 'prod'),
        ('spring.profiles.group.my-prod=dev\n', 'myprod'),
        ('spring.profiles.group.my_prod=dev\n', 'my-prod'),
        ('spring.profiles.group.myprod=dev\n', 'my-prod'),
        ('spring.profiles.group.prod=dev\n', 'Prod'),
      ]) {
        write('application.properties', file);
        final e = env({'spring.profiles.active': active});
        process(e);
        expect(e.activeProfiles, [active], reason: file);
      }
      File('$root/application.properties').deleteSync();
      write(
        'application.yaml',
        'spring.profiles:\n  group:\n    myProd: dev\n  active: myprod\n',
      );
      final yaml = env();
      process(yaml);
      expect(yaml.activeProfiles, ['myprod']);
    });

    test('the prefix is relaxed; lists, dotted names and environment '
        'variables work', () {
      for (final (file, active, expected) in [
        ('spring.Profiles.GROUP.prod=dev\n', 'prod', ['prod', 'dev']),
        (
          'spring.profiles.group.prod[0]=dev\n'
              'spring.profiles.group.prod[1]=eu\n',
          'prod',
          ['prod', 'dev', 'eu'],
        ),
        ('spring.profiles.group.my.prod=dev\n', 'my.prod', ['my.prod', 'dev']),
        ('spring.profiles.group[my.prod]=dev\n', 'my.prod', ['my.prod', 'dev']),
        // Two spellings of one name: Boot's binder finds the first one's
        // value for both map keys.
        (
          'spring.profiles.group.prod=dev\nspring.profiles.group.Prod=eu\n',
          'Prod',
          ['Prod', 'dev'],
        ),
      ]) {
        write('application.properties', file);
        final e = env({'spring.profiles.active': active});
        process(e);
        expect(e.activeProfiles, expected, reason: file);
      }
      final variables = StandardEnvironment(
        systemEnvironment: {
          'SPRING_PROFILES_GROUP_PROD': 'dev',
          'SPRING_PROFILES_ACTIVE': 'prod',
        },
      );
      File('$root/application.properties').deleteSync();
      process(variables);
      expect(variables.activeProfiles, ['prod', 'dev']);
    });
  });

  // A file that is not UTF-8 failed with a bare FormatException ("Missing
  // extension byte"), naming no file.
  group('a config file that is not valid UTF-8 is named', () {
    final latin1Bytes = [...'name=caf'.codeUnits, 0xe9, 0x0a];

    test('read synchronously', () {
      File('$root/application.properties')
        ..createSync(recursive: true)
        ..writeAsBytesSync(latin1Bytes);
      expect(
        () => process(env()),
        throwsA(
          isA<ConfigDataLoadException>()
              .having((e) => e.location, 'location', contains('application'))
              .having((e) => e.message, 'message', contains('UTF-8')),
        ),
      );
      // ISO-8859-1, as Spring Boot reads .properties files.
      final e = env();
      ConfigDataEnvironment(
        e,
        defaultLocations: ['optional:file:$root/'],
        loaders: const [PropertiesPropertySourceLoader(encoding: latin1)],
      ).processAndApplySync();
      expect(e.getProperty('name'), 'café');
    });

    test('read asynchronously', () async {
      final e = env();
      final run = ConfigDataEnvironment(
        e,
        resourceLoader: DefaultResourceLoader(
          protocolResolvers: [_AsyncBytes('async:', latin1Bytes)],
        ),
        defaultLocations: const ['optional:async:/'],
      ).processAndApply();
      await expectLater(
        run,
        throwsA(
          isA<ConfigDataLoadException>()
              .having(
                (e) => e.location,
                'location',
                'async:/application.properties',
              )
              .having((e) => e.message, 'message', contains('UTF-8')),
        ),
      );
    });
  });

  // Only a single trailing extension hint was known, so
  // `x.properties[encoding=iso-8859-1]` failed with "File extension is
  // not known" and `x.conf[encoding=utf-8][.yml]` or `sub[x]/y.yml` were
  // "not found". Expected values: Spring Boot 4.1.2 over the same files.
  group('Spring Boot 4.1 file hints', () {
    void writeLatin1(String path, String content) => File('$root/$path')
      ..createSync(recursive: true)
      ..writeAsBytesSync(latin1.encode(content));

    String? importing(String location, {String? property = 'a'}) {
      write('application.properties', 'spring.config.import=$location\n');
      final e = env();
      process(e);
      return property == null ? null : e.getProperty(property);
    }

    Matcher failsWith(String text) => throwsA(
      isA<ConfigDataLoadException>().having(
        (e) => e.message,
        'message',
        contains(text),
      ),
    );

    test('an encoding, an extension, several in any order', () {
      write('x.conf', 'a=café\n');
      expect(importing('x.conf[.properties][encoding=utf-8]'), 'café');
      write('x.conf', 'a: café\n');
      expect(importing('x.conf[encoding=utf-8][.yml]'), 'café');
      write('x.yml', 'a: café\n');
      expect(importing('x.yml[encoding=utf-8]'), 'café');
      // The last extension and the last encoding win.
      write('x.conf', 'a=props\n');
      expect(importing('x.conf[.yml][.properties]'), 'props');
      writeLatin1('x.properties', 'a=café\n');
      writeLatin1('d1/x.properties', 'a=café\n');
      for (final location in [
        'x.properties[encoding=iso-8859-1]',
        'x.properties[ encoding = ISO-8859-1 ]',
        'x.properties[encoding=utf-8][encoding=iso-8859-1]',
        '*/x.properties[encoding=iso-8859-1]',
      ]) {
        expect(importing(location), 'café', reason: location);
      }
      final e = env({
        'spring.config.location':
            'file:$root/x.properties[encoding=iso-8859-1]',
      });
      process(e);
      expect(e.getProperty('a'), 'café');
    });

    test("Java's names and aliases, without case", () {
      writeLatin1('x.properties', 'a=café\n');
      for (final name in [
        'latin1',
        'LATIN1',
        'l1',
        '8859_1',
        'ISO8859-1',
        'iso_8859-1:1987',
        'cp819',
        'csISOLatin1',
      ]) {
        expect(
          importing('x.properties[encoding=$name]'),
          'café',
          reason: name,
        );
      }
      write('x.properties', 'a=café\n');
      for (final name in ['utf8', 'UTF8', 'unicode-1-1-utf-8']) {
        expect(
          importing('x.properties[encoding=$name]'),
          'café',
          reason: name,
        );
      }
      write('x.properties', 'a=cafe\n');
      for (final name in ['ascii', 'US-ASCII', 'us', '646']) {
        expect(
          importing('x.properties[encoding=$name]'),
          'cafe',
          reason: name,
        );
      }
    });

    test('a charset that cannot be read fails, also when optional and '
        'for YAML', () {
      write('x.properties', 'a=cafe\n');
      write('x.yml', 'a: cafe\n');
      for (final location in [
        // Not Java's (Charset.forName refuses them too).
        'x.properties[encoding=bogus]',
        'optional:x.properties[encoding=bogus]',
        'x.properties[encoding=Latin-1]',
        'x.properties[encoding=csutf8]',
        'optional:missing.yml[encoding=bogus]',
        // Java's, not decodable here.
        'x.properties[encoding=UTF-16]',
        'x.yml[encoding=windows-1252]',
      ]) {
        expect(
          () => importing(location),
          throwsA(
            isA<ConfigDataLoadException>()
                .having((e) => e.location, 'location', location)
                .having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains('unsupported charset'),
                    contains('UTF-8, ISO-8859-1 and US-ASCII'),
                  ),
                ),
          ),
          reason: location,
        );
      }
      for (final location in [
        'x.properties[encoding=]',
        'x.properties[encoding=bad name]',
      ]) {
        expect(
          () => importing(location),
          failsWith('is not a charset name'),
          reason: location,
        );
      }
      // An attribute name has case: `ENCODING` is no encoding hint.
      expect(importing('x.properties[ENCODING=bogus]'), 'cafe');
    });

    // As Boot's YamlPropertySourceLoader, which ignores the encoding.
    test('YAML is read as UTF-8 whatever the hint', () {
      writeLatin1('x.yml', 'a: café\n');
      expect(
        () => importing('x.yml[encoding=iso-8859-1]'),
        failsWith('not valid UTF-8'),
      );
    });

    test('a profile variant gets the encoding', () {
      writeLatin1('x.properties', 'a=café\n');
      writeLatin1('x-dev.properties', 'b=dév\n');
      writeLatin1('x.conf', 'a=café\n');
      writeLatin1('x.conf-dev', 'b=dév\n');
      for (final location in [
        'x.properties[encoding=iso-8859-1]',
        'x.conf[.properties][encoding=iso-8859-1]',
      ]) {
        write(
          'application.properties',
          'spring.profiles.active=dev\nspring.config.import=$location\n',
        );
        final e = env();
        process(e);
        expect(e.getProperty('a'), 'café', reason: location);
        expect(e.getProperty('b'), 'dév', reason: location);
      }
    });

    test('every bracketed part leaves the path of a file, not of a '
        'directory', () {
      write('sub/y.yml', 'a: fromsub\n');
      expect(importing('sub[x]/y.yml'), 'fromsub');
      write('x.yml', 'a: x\n');
      for (final location in ['x.yml[foo]', 'x.yml[x=y]', 'x.yml[]']) {
        expect(importing(location), 'x', reason: location);
      }
      write('x', 'a: hinted\n');
      expect(importing('x[.yml]]'), 'hinted');
      expect(importing('x[ .yml ]'), 'hinted');
      // `.yml` must have its dot; brackets in brackets are no hint.
      for (final location in ['x[yml]', 'x[[.yml]]']) {
        expect(
          () => importing(location),
          failsWith('File extension is not known'),
          reason: location,
        );
      }
      write('conf[x]/application.properties', 'a=dirbracket\n');
      expect(importing('conf[x]/'), 'dirbracket');
      // Not found: reported as written.
      expect(
        () => importing('missing.yml[encoding=utf-8]'),
        throwsA(
          isA<ConfigDataResourceNotFoundException>().having(
            (e) => e.location,
            'location',
            'missing.yml[encoding=utf-8]',
          ),
        ),
      );
    });

    test('ConfigDataEnvironment.fileHints reads a location so', () {
      final hints = ConfigDataEnvironment.fileHints(
        'classpath:conf[x]/dev.conf[encoding=Latin1][.properties]',
      );
      expect(hints.path, 'classpath:conf/dev.conf');
      expect(hints.extension, 'properties');
      expect(hints.encoding, latin1);
      final none = ConfigDataEnvironment.fileHints('x.yml[foo]');
      expect((none.path, none.extension, none.encoding), ('x.yml', null, null));
      expect(
        () => ConfigDataEnvironment.fileHints('x.yml[encoding=utf-16]'),
        throwsA(isA<ConfigDataLoadException>()),
      );
    });

    test('fileHints leaves a directory or config tree location as it is, '
        'keeps optional: and refuses a ; group', () {
      for (final location in [
        'sub[x]/',
        'optional:file:./conf[encoding=latin1]/',
        'configtree:tree[encoding=latin1]/',
        'optional:configtree:/run/[x]/',
      ]) {
        final hints = ConfigDataEnvironment.fileHints(location);
        expect(
          (hints.path, hints.extension, hints.encoding),
          (location, null, null),
          reason: location,
        );
      }
      final optional = ConfigDataEnvironment.fileHints(
        'optional:conf[x]/app.conf[.yml]',
      );
      expect(
        (optional.path, optional.extension),
        ('optional:conf/app.conf', 'yml'),
      );
      expect(
        () => ConfigDataEnvironment.fileHints('a.conf[.yml];b.conf'),
        throwsArgumentError,
      );
    });

    test('read asynchronously', () async {
      final e = env({
        'spring.config.location':
            'async:/application.properties[encoding=latin1]',
      });
      await ConfigDataEnvironment(
        e,
        resourceLoader: DefaultResourceLoader(
          protocolResolvers: [
            _AsyncBytes('async:', [...'name=caf'.codeUnits, 0xe9, 0x0a]),
          ],
        ),
      ).processAndApply();
      expect(e.getProperty('name'), 'café');
    });
  });

  // Boot reads `.xml` with java.util.Properties.loadFromXML; this failed
  // with "File extension is not known to any PropertySourceLoader".
  test('an .xml import says XML properties are not supported', () {
    write('application.properties', 'spring.config.import=x.xml\n');
    write('x.xml', '<properties/>');
    expect(
      () => process(env()),
      throwsA(
        isA<ConfigDataLoadException>().having(
          (e) => e.message,
          'message',
          contains('XML properties files are not supported'),
        ),
      ),
    );
  });

  // The documents were split with a regular expression before continued
  // lines were joined, so `a=base\` followed by `#---` started a new
  // document (Boot: `a=base#---` and the next lines in the same one), a
  // `#---` right after a `#` comment was a separator, `[]` lists were a key
  // `hosts[]`. Expected values: Spring Boot 4.1.2's
  // PropertiesPropertySourceLoader over the same text.
  group('.properties documents are read as Spring Boot reads them', () {
    List<Map<String, Object?>> documents(String text) => [
      for (final source in const PropertiesPropertySourceLoader().load(
        'x',
        text,
      ))
        (source as MapPropertySource).source,
    ];

    // Each line holding only `\` recursed once (Boot's CharacterReader
    // does too, and overflows near 10,000): 100,000 of them ended in a raw
    // StackOverflowError naming no file.
    test('any number of lines holding only a backslash is read', () {
      final lines = '\\\n' * 100000;
      // What Boot reads from 100 such lines.
      expect(documents('a=\\\n${lines}b=2\n'), [
        {'a': 'b=2'},
      ]);
      expect(documents('$lines#---\nb=2\n'), [
        {'b': '2'},
      ]);
      write('application.properties', 'a=\\\n${lines}b=2\n');
      final e = env();
      process(e);
      expect(e.getProperty('a'), 'b=2');
    });

    test("a loader's stack overflow fails naming the file", () {
      write('application.deep', 'x');
      expect(
        () => ConfigDataEnvironment(
          env(),
          loaders: [const PropertiesPropertySourceLoader(), _Recursing()],
          defaultLocations: ['optional:file:$root/'],
        ).processAndApplySync(),
        throwsA(
          isA<ConfigDataLoadException>()
              .having((e) => e.location, 'location', endsWith('.deep'))
              .having(
                (e) => e.message,
                'message',
                contains('overflowed the stack'),
              ),
        ),
      );
    });

    test('a separator only starts a fresh logical line', () {
      for (final (text, expected) in [
        // Continued into the separator: one document.
        (
          'a=base\\\n#---\nb=x\n',
          [
            {'a': 'base#---', 'b': 'x'},
          ],
        ),
        (
          'a=base\\\n  !---\nb=x\n',
          [
            {'a': 'base!---', 'b': 'x'},
          ],
        ),
        // After a comment of the same prefix: a comment.
        (
          'a=1\n# note\n#---\nb=2\n',
          [
            {'a': '1', 'b': '2'},
          ],
        ),
        (
          'a=1\n! note\n#---\nb=2\n',
          [
            {'a': '1'},
            {'b': '2'},
          ],
        ),
        // Leading blanks, a fourth hyphen: a comment; trailing blanks and
        // `!---`: separators.
        (
          'a=1\n  #---\nb=2\n',
          [
            {'a': '1', 'b': '2'},
          ],
        ),
        (
          'a=1\n#----\nb=2\n#--- \t\nc=3\n!---\nd=4\n',
          [
            {'a': '1', 'b': '2'},
            {'c': '3'},
            {'d': '4'},
          ],
        ),
        (
          'a=1\r\n#---\r\nb=2\r#---\rc=3',
          [
            {'a': '1'},
            {'b': '2'},
            {'c': '3'},
          ],
        ),
      ]) {
        expect(documents(text), expected, reason: text);
      }
    });

    test('through the config data loader', () {
      write(
        'application.properties',
        'a=base\\\n#---\nspring.config.activate.on-profile=dev\nb=x\n',
      );
      final e = env();
      process(e);
      // One document, for dev only.
      expect(e.getProperty('a'), isNull);
      expect(e.getProperty('b'), isNull);
    });

    test('[] lists, empty keys, documents named by the ones kept', () {
      expect(documents('hosts[]=a, b,c\nempty[] =\n=x\n  =y\n'), [
        {'hosts[0]': 'a', 'hosts[1]': 'b', 'hosts[2]': 'c', 'empty[0]': ''},
      ]);
      expect(
        const PropertiesPropertySourceLoader()
            .load('x', '#---\na=1\n')
            .single
            .name,
        'x',
      );
    });

    // The two documented differences: Boot joins a document whose first
    // line is a comment to the one before, and after blanks behind a
    // separator drops the next line when it starts with blanks.
    test('a comment after a separator, blanks around: documents kept', () {
      expect(documents('a=1\n#---\n# the dev document\nb=2\n'), [
        {'a': '1'},
        {'b': '2'},
      ]);
      expect(documents('a=1\n#--- \n  b=2\n'), [
        {'a': '1'},
        {'b': '2'},
      ]);
    });
  });

  // Checked with Spring Boot 4.1.2: its binder's list binding fails on a
  // bracketed element it cannot place, and scalars ignore list forms.
  group('list and scalar keys are bound as Boot binds them', () {
    Matcher unbound(String element) => throwsA(
      isA<InvalidConfigDataPropertyException>()
          .having((e) => e.property, 'property', element)
          .having((e) => e.reason, 'reason', contains('left unbound')),
    );

    test('a list element that is not [0], [1]... fails the start', () {
      write('x.properties', 'b=x\n');
      for (final (content, element) in [
        ('spring.config.import[x]=x.properties', 'spring.config.import[x]'),
        ('spring.config.import[1]=x.properties', 'spring.config.import[1]'),
        (
          'spring.config.import[0].foo=x.properties',
          'spring.config.import[0].foo',
        ),
        ('spring.profiles.active[x]=dev', 'spring.profiles.active[x]'),
        ('spring.profiles.include[x]=dev', 'spring.profiles.include[x]'),
        (
          '#---\nspring.config.activate.on-profile[x]=dev',
          'spring.config.activate.on-profile[x]',
        ),
        // Boot binds the imports of every document, applied or not.
        (
          '#---\nspring.config.activate.on-profile=prod\n'
              'spring.config.import[x]=x.properties',
          'spring.config.import[x]',
        ),
      ]) {
        write('application.properties', 'a=base\n$content\n');
        expect(() => process(env()), unbound(element), reason: content);
      }
      write('application.properties', 'a=base\n');
      expect(
        () => process(env({'spring.config.import[x]': 'x.properties'})),
        unbound('spring.config.import[x]'),
      );
      expect(
        () => process(env({'spring.config.name[x]': 'x'})),
        unbound('spring.config.name[x]'),
      );
    });

    test("next to the key's own value, elements are not looked at", () {
      write('x.properties', 'b=x\n');
      write(
        'application.properties',
        'spring.config.import=x.properties\n'
            'spring.config.import[x]=y.properties\n',
      );
      final e = env();
      process(e);
      expect(e.getProperty('b'), 'x');
    });

    test('on-cloud-platform and spring.main.cloud-platform are scalars: a '
        'list form is no guard and forces nothing', () {
      write(
        'application.properties',
        'a=base\n#---\n'
            'spring.config.activate.on-cloud-platform[0]=kubernetes\n'
            'b=doc2\n'
            '#---\n'
            'spring.config.activate.on-cloud-platform=kubernetes\n'
            'c=k8s\n',
      );
      final e = env({'spring.main.cloud-platform[0]': 'kubernetes'});
      process(e);
      expect(e.getProperty('b'), 'doc2');
      expect(e.getProperty('c'), isNull);
      final forced = env({'spring.main.cloud-platform': 'kubernetes'});
      process(forced);
      expect(forced.getProperty('c'), 'k8s');
    });
  });

  // Boot picks the resolver of a `;` group from its first entry; Dart reads
  // each entry by its own prefix (a documented difference).
  test('configtree: in a ; group is read as a config tree', () {
    write('tree/c', 'tree');
    write('x.yaml', 'b: x\n');
    for (final group in [
      'x.yaml;configtree:$root/tree/',
      'configtree:$root/tree/;x.yaml',
    ]) {
      write('application.properties', 'spring.config.import=$group\n');
      final e = env();
      process(e);
      expect(e.getProperty('b'), 'x', reason: group);
      expect(e.getProperty('c'), 'tree', reason: group);
    }
  });
}

// Serves [bytes] as `application.properties` under [prefix], readable
// only asynchronously (as a Flutter asset or an `http:` file is).
final class _AsyncBytes implements ProtocolResolver {
  _AsyncBytes(this.prefix, this.bytes);

  final String prefix;
  final List<int> bytes;

  @override
  Resource? resolve(String location, ResourceLoader resourceLoader) {
    if (!location.startsWith(prefix)) {
      return null;
    }
    return _AsyncResource(
      location,
      location.endsWith('/application.properties') ? bytes : null,
    );
  }
}

final class _AsyncResource extends AbstractResource {
  _AsyncResource(this.description, this._bytes);

  @override
  final String description;
  final List<int>? _bytes;

  @override
  bool exists() => _bytes != null;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList(_bytes!);
}

// A loader of `.deep` files that recurses without end.
final class _Recursing extends PropertySourceLoader {
  @override
  List<String> get fileExtensions => const ['deep'];

  @override
  List<AbstractPropertySource<Object>> load(String name, String content) =>
      _depth(content, 0);

  List<AbstractPropertySource<Object>> _depth(String content, int depth) =>
      depth < 0 ? const [] : _depth(content, depth + 1);
}
