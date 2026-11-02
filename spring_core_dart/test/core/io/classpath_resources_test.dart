@TestOn('vm')
library;

import 'dart:io';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

void main() {
  ClasspathResources.registerAll(const {
    'app/greeting.txt': EmbeddedResource.text('hello'),
    'app/logo.bin': EmbeddedResource.base64('AAEC'),
    'config/application.properties': EmbeddedResource.text('from=classpath'),
  });

  test('resources: serves embedded text and binary files', () {
    final loader = DefaultResourceLoader();
    expect(
      loader.getResource('resources:app/greeting.txt').readAsStringSync(),
      'hello',
    );
    expect(loader.getResource('resources:/app/logo.bin').readAsBytesSync(), [
      0,
      1,
      2,
    ]);
    expect(
      loader.getResource('resources:app/./greeting.txt').description,
      'class path resource [app/greeting.txt]',
    );
  });

  test('the first registration of a path wins', () {
    ClasspathResources.registerAll(const {
      'app/greeting.txt': EmbeddedResource.text('other'),
    });
    expect(
      ClasspathResources.resolve('app/greeting.txt').readAsStringSync(),
      'hello',
    );
  });

  test('@Value-style conversion String -> Resource', () {
    final resource = DefaultConversionService().convert<Resource>(
      'resources:app/greeting.txt',
    );
    expect(resource.readAsStringSync(), 'hello');
  });

  test('config data reads resources:/config/ by default', () {
    final environment = StandardEnvironment(systemEnvironment: {});
    ConfigDataEnvironment(environment).processAndApplySync();
    expect(environment.getProperty('from'), 'classpath');
  });

  group('the former classpath: prefix', () {
    late List<String> warnings;
    late void Function() stop;
    setUp(() {
      ClasspathResources.resetLegacyWarnings();
      warnings = [];
      stop = SpringLog.listen((record) {
        if (record.level == SpringLogLevel.warning) {
          warnings.add(record.message);
        }
      });
    });
    tearDown(() => stop());

    test('resolves like resources: and warns once per location', () {
      final loader = DefaultResourceLoader();
      final old = loader.getResource('classpath:app/greeting.txt');
      expect(old.readAsStringSync(), 'hello');
      expect(
        old.readAsStringSync(),
        loader.getResource('resources:app/greeting.txt').readAsStringSync(),
      );
      loader
        ..getResource('classpath:app/greeting.txt')
        ..getResource('classpath:app/logo.bin');
      expect(warnings, hasLength(2));
      expect(
        warnings.first,
        "'classpath:app/greeting.txt' uses the prefix classpath:, which is "
        'now resources: (classpath: is refused in the next minor release)',
      );
    });

    test('resources: and plain paths do not warn', () {
      DefaultResourceLoader()
        ..getResource('resources:app/greeting.txt')
        ..getResource('app/greeting.txt');
      expect(warnings, isEmpty);
    });

    test('classpath*: patterns work and warn with resources*:', () {
      final found = PathMatchingResourcePatternResolver().getResources(
        'classpath*:app/*.txt',
      );
      expect(found.map((r) => r.readAsStringSync()), ['hello']);
      expect(warnings.single, contains('resources*:'));
    });

    test('spring.config.import with classpath: loads and warns', () {
      final environment = StandardEnvironment(
        systemEnvironment: {
          'SPRING_CONFIG_IMPORT':
              'optional:classpath:config/application.properties',
        },
      );
      ConfigDataEnvironment(environment).processAndApplySync();
      expect(environment.getProperty('from'), 'classpath');
      expect(warnings, hasLength(1));
      expect(warnings.single, startsWith("'classpath:config/application"));
    });

    test('the default locations do not warn', () {
      final environment = StandardEnvironment(systemEnvironment: {});
      ConfigDataEnvironment(environment).processAndApplySync();
      expect(warnings, isEmpty);
    });
  });

  test('an unknown path is not embedded', () {
    expect(ClasspathResources.resolve('missing.txt').exists(), isFalse);
  });

  test('added directories shadow embedded files, newest first', () {
    final test = Directory.systemTemp.createTempSync('cp_test_');
    final other = Directory.systemTemp.createTempSync('cp_other_');
    addTearDown(() {
      test.deleteSync(recursive: true);
      other.deleteSync(recursive: true);
    });
    File('${test.path}/app/greeting.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('from test resources');
    File('${test.path}/only-in-test.txt').writeAsStringSync('test only');
    File('${other.path}/only-in-test.txt').writeAsStringSync('newest');

    final removeTest = ClasspathResources.addDirectory('${test.path}/');
    final loader = DefaultResourceLoader();
    String read(String location) =>
        loader.getResource(location).readAsStringSync();

    expect(read('resources:app/greeting.txt'), 'from test resources');
    expect(read('resources:/only-in-test.txt'), 'test only');
    expect(read('resources:app/logo.bin'), isNotEmpty); // embedded fallback

    final removeOther = ClasspathResources.addDirectory(other.path);
    expect(ClasspathResources.directories, [other.path, test.path]);
    expect(read('resources:only-in-test.txt'), 'newest');
    removeOther();
    removeOther(); // idempotent

    removeTest();
    expect(ClasspathResources.directories, isEmpty);
    expect(read('resources:app/greeting.txt'), isNot('from test resources'));
    expect(ClasspathResources.resolve('only-in-test.txt').exists(), isFalse);
  });

  group('a path that climbs above lib/resources/ finds nothing', () {
    // The tests run in the package directory: ../../pubspec.yaml from
    // lib/resources/ is the package's pubspec.yaml, which exists.
    const above = '../../pubspec.yaml';

    test('as a location, with or without resources: and a leading /', () {
      // What the location used to read.
      expect(
        FileSystemResource('${ClasspathResources.directory}/$above').exists(),
        isTrue,
      );
      final loader = DefaultResourceLoader();
      for (final location in [
        'resources:$above',
        'resources:/$above',
        'resources:app/../$above',
        r'resources:..\..\pubspec.yaml',
        above,
      ]) {
        final resource = loader.getResource(location);
        expect(resource.exists(), isFalse, reason: location);
        expect(resource.isReadable, isFalse, reason: location);
        expect(
          resource.description,
          'class path resource [$above]',
          reason: location,
        );
        expect(resource.readAsStringSync, throwsStateError, reason: location);
        expect(resource.readAsBytes(), throwsStateError, reason: location);
      }
      expect(ClasspathResources.resolveEmbedded(above).exists(), isFalse);
    });

    test('relative to an embedded file', () {
      final greeting = ClasspathResources.resolve('resources:app/greeting.txt');
      expect(greeting.createRelative('../$above').exists(), isFalse);
      expect(
        greeting.createRelative('../config/application.properties').exists(),
        isTrue,
      );
      final outside = greeting.createRelative('../$above');
      expect(outside.createRelative('x.txt').exists(), isFalse);
    });

    test('in an added directory', () {
      final root = Directory.systemTemp.createTempSync('cp_above_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/resources').createSync();
      File('${root.path}/secret.txt').writeAsStringSync('secret');
      final remove = ClasspathResources.addDirectory('${root.path}/resources');
      addTearDown(remove);
      expect(ClasspathResources.resolve('../secret.txt').exists(), isFalse);
      expect(
        PathMatchingResourcePatternResolver().getResources(
          'resources*:../secret.txt',
        ),
        isEmpty,
      );
    });

    test('in patterns', () {
      final resolver = PathMatchingResourcePatternResolver();
      for (final pattern in [
        'resources*:$above',
        'resources*:../../*.yaml',
        'resources*:../../**/*.yaml',
        'resources:../../*.yaml',
        '../../*.yaml',
      ]) {
        expect(resolver.getResources(pattern), isEmpty, reason: pattern);
      }
    });

    test('normalize resolves . and .., and refuses climbing above', () {
      expect(
        ClasspathResources.normalize('/config/./app.properties'),
        'config/app.properties',
      );
      expect(ClasspathResources.normalize(r'a\..\b//c'), 'b/c');
      for (final path in ['..', '../x', 'a/../../x', '/../x']) {
        expect(ClasspathResources.normalize(path), isNull, reason: path);
      }
    });
  });

  // The embedded paths are normalized: a pattern written with `./`, `..`
  // or `//` matched none of them.
  test('patterns with ., .. and empty segments find embedded files', () {
    ClasspathResources.registerAll(const {
      'emb/a.txt': EmbeddedResource.text('a'),
      'emb/b.txt': EmbeddedResource.text('b'),
      'emb/c.bin': EmbeddedResource.base64('AA=='),
    });
    final resolver = PathMatchingResourcePatternResolver();
    for (final pattern in [
      'resources:emb/*.txt',
      'resources:./emb/*.txt',
      'resources:sub/../emb/*.txt',
      'resources:emb//*.txt',
      'resources:/./emb/./*.txt',
      'resources*:./emb/*.txt',
      'resources*:sub/../emb/*.txt',
      'resources*:emb//*.txt',
      './emb/*.txt',
    ]) {
      expect(
        [for (final r in resolver.getResources(pattern)) r.readAsStringSync()],
        ['a', 'b'],
        reason: pattern,
      );
    }
    expect(
      resolver.getResources('resources*:./emb/../emb/c.bin').single.filename,
      'c.bin',
    );
    expect(resolver.getResources('resources:emb/../../emb/*.txt'), isEmpty);
  });

  test('normalized patterns also find files of added directories', () {
    final root = Directory.systemTemp.createTempSync('cp_pattern_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/dir').createSync();
    File('${root.path}/dir/x.txt').writeAsStringSync('x');
    final remove = ClasspathResources.addDirectory(root.path);
    addTearDown(remove);
    final resolver = PathMatchingResourcePatternResolver();
    for (final pattern in [
      'resources:./dir/*.txt',
      'resources:other/../dir/*.txt',
      'resources*:dir//*.txt',
    ]) {
      expect(
        [for (final r in resolver.getResources(pattern)) r.readAsStringSync()],
        ['x'],
        reason: pattern,
      );
    }
  });

  // Spring 7 cleans the part of a pattern after its root directory too
  // (StringUtils.cleanPath(subPattern) in doFindPathMatchingFileResources):
  // `\` is a separator there and `.` and `..` segments are resolved. It
  // was matched as written, so these patterns found other files than in
  // Spring (Spring 7.0.10: `resources*:mail/{n:\w+}.txt` finds nothing,
  // `resources*:mail\*.txt` and `resources*:mail/*/../*.txt` find
  // `mail/*.txt`).
  group('the rest of a classpath pattern is cleaned as in Spring', () {
    late PathMatchingResourcePatternResolver resolver;
    List<String> read(String pattern) => [
      for (final r in resolver.getResources(pattern)) r.readAsStringSync(),
    ];

    setUp(() {
      ClasspathResources.registerAll(const {
        'mail/a.txt': EmbeddedResource.text('a'),
        'mail/b1.txt': EmbeddedResource.text('b1'),
      });
      final root = Directory.systemTemp.createTempSync('cp_clean_');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/letters/c.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('c');
      addTearDown(ClasspathResources.addDirectory(root.path));
      resolver = PathMatchingResourcePatternResolver();
    });

    test(r'a \ in a {name:regex} becomes / and matches nothing', () {
      for (final prefix in ['resources:', 'resources*:', '']) {
        expect(read('${prefix}mail/{n:\\w+}.txt'), isEmpty, reason: prefix);
        expect(read('${prefix}mail/{n:[a-z]\\d}.txt'), isEmpty);
        expect(read('${prefix}letters/{n:\\w}.txt'), isEmpty);
        // Character classes instead.
        expect(read('${prefix}mail/{n:[a-z0-9]+}.txt'), ['a', 'b1']);
        expect(read('${prefix}mail/{n:[a-z][0-9]}.txt'), ['b1']);
        expect(read('${prefix}letters/{n:[a-z]}.txt'), ['c']);
      }
    });

    test(r'\ is a separator, also before the first wildcard', () {
      // `mail\*.txt` has no `/`: its root directory is the classpath root,
      // whose first one (the added directory) has no mail/ for resources:.
      expect(read(r'resources*:mail\*.txt'), ['a', 'b1']);
      expect(read(r'resources*:letters\*.txt'), ['c']);
      expect(read(r'resources:letters\*.txt'), ['c']);
      expect(read(r'resources:mail\*.txt'), isEmpty);
      expect(read(r'resources*:mail\{n:[a-z]}.txt'), ['a']);
    });

    test('. and .. after the first wildcard are resolved', () {
      for (final prefix in ['resources:', 'resources*:', '']) {
        expect(read('${prefix}mail/*/../*.txt'), ['a', 'b1'], reason: prefix);
        expect(read('${prefix}mail/*/./../*/../{n:[a-z]}.txt'), ['a']);
        expect(read('${prefix}letters/./*.txt'), ['c']);
        expect(read('${prefix}mail/*/../b1.txt'), ['b1']);
      }
      // The directory before the first wildcard is still normalized.
      expect(read('resources*:./x/../mail//*/../*.txt'), ['a', 'b1']);
    });

    test('a .. above the roots or the root directory finds nothing', () {
      expect(read('resources:mail/../../{n:[a-z]}.txt'), isEmpty);
      expect(read('resources*:mail/*/../../*.txt'), isEmpty);
      expect(read('resources*:mail/*/../../mail/*.txt'), isEmpty);
      expect(read('resources*:letters/*/../../letters/*.txt'), isEmpty);
    });
  });

  // The same rule for `file:` patterns: the rest is cleaned on its own,
  // so a `..` cannot climb above the directory walked (Spring 7.0.10:
  // `file:dir/mail/*/../../*.txt` finds nothing).
  test('a file: pattern cleans its rest as in Spring', () {
    final root = Directory.systemTemp.createTempSync('file_clean_');
    addTearDown(() => root.deleteSync(recursive: true));
    final base = root.path.replaceAll(r'\', '/');
    for (final path in ['top.txt', 'mail/a.txt', 'mail/b1.txt']) {
      File('$base/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(path);
    }
    final resolver = PathMatchingResourcePatternResolver();
    List<String> read(String pattern) => [
      for (final r in resolver.getResources(pattern)) r.readAsStringSync(),
    ];

    expect(read('file:$base/mail/*/../*.txt'), ['mail/a.txt', 'mail/b1.txt']);
    expect(read('file:$base/mail\\*.txt'), ['mail/a.txt', 'mail/b1.txt']);
    expect(read('file:$base/**/./top.txt'), ['top.txt']);
    expect(read('file:$base/mail/{n:\\w+}.txt'), isEmpty);
    expect(read('file:$base/mail/*/../../*.txt'), isEmpty);
    expect(read('file:$base/*/../top.txt'), ['top.txt']);
  });

  // Spring's StringUtils.cleanPath turns each `\\` (two backslashes) into
  // one `/` before the single ones, so in `*\\..\\*.txt` the `..` removes
  // the `*` directory: Spring 7.0.10 finds `mail/*.txt`. Each `\` was read
  // as `/` alone: `*//..//*.txt`, whose `..` removed an empty segment, found
  // `mail/sub/inner.txt` instead.
  test(r'\\ is one separator, as in Spring', () {
    ClasspathResources.registerAll(const {
      'bs/a.txt': EmbeddedResource.text('a'),
      'bs/b.txt': EmbeddedResource.text('b'),
      'bs/sub/inner.txt': EmbeddedResource.text('inner'),
    });
    final root = Directory.systemTemp.createTempSync('backslash_clean_');
    addTearDown(() => root.deleteSync(recursive: true));
    final base = root.path.replaceAll(r'\', '/');
    for (final path in ['bs/a.txt', 'bs/b.txt', 'bs/sub/inner.txt']) {
      File('$base/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          path.substring(path.lastIndexOf('/') + 1, path.length - 4),
        );
    }
    final resolver = PathMatchingResourcePatternResolver();
    List<String> read(String pattern) => [
      for (final r in resolver.getResources(pattern)) r.readAsStringSync(),
    ];

    for (final prefix in ['resources:', 'resources*:', '', 'file:$base/']) {
      expect(read('${prefix}bs/*\\\\..\\\\*.txt'), ['a', 'b'], reason: prefix);
      expect(read('${prefix}bs/sub\\\\..\\\\*.txt'), [
        'a',
        'b',
      ], reason: prefix);
      expect(read('${prefix}bs/**\\\\..\\\\*.txt'), ['a', 'b'], reason: prefix);
      // Three backslashes are `/` and `/`; four are two `/`: the `..`
      // removes an empty segment again (as in Spring).
      expect(read('${prefix}bs/*\\\\\\..\\\\\\*.txt'), [
        'inner',
      ], reason: prefix);
      expect(
        read('${prefix}bs/*\\\\\\\\..\\\\\\\\*.txt'),
        ['inner'],
        reason: prefix,
      );
      // Single ones, as before.
      expect(read('${prefix}bs/sub\\..\\*.txt'), ['a', 'b'], reason: prefix);
    }
  });

  test('an owner registering again replaces its own files only', () {
    String read(String path) =>
        ClasspathResources.resolve(path).readAsStringSync();
    ClasspathResources.registerAll(const {
      'reload/app.properties': EmbeddedResource.text('v=1'),
      'reload/old.txt': EmbeddedResource.text('old'),
    }, owner: 'app');
    ClasspathResources.registerAll(const {
      'reload/app.properties': EmbeddedResource.text('starter'),
      'reload/starter.txt': EmbeddedResource.text('s'),
    }, owner: 'starter');
    expect(read('reload/app.properties'), 'v=1'); // first owner wins

    // The app module rebuilt after a hot reload: changed and removed files.
    ClasspathResources.registerAll(const {
      'reload/app.properties': EmbeddedResource.text('v=2'),
    }, owner: 'app');
    expect(read('reload/app.properties'), 'v=2');
    expect(ClasspathResources.resolve('reload/old.txt').exists(), isFalse);
    expect(read('reload/starter.txt'), 's'); // other owners untouched
  });
}
