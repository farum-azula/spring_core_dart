import 'dart:io';

import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('scd_io_fixes_'));
  tearDown(() => temp.deleteSync(recursive: true));

  File write(String path, String content) => File('${temp.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  group('classpath patterns', () {
    late List<void Function()> removals;

    setUp(() {
      write('one/i18n/a.properties', 'a=1');
      write('one/i18n/sub/b.properties', 'b=1');
      write('two/i18n/a.properties', 'a=2');
      write('two/other/c.properties', 'c=2');
      // Added later, so `two` is searched first.
      removals = [
        ClasspathResources.addDirectory('${temp.path}/one'),
        ClasspathResources.addDirectory('${temp.path}/two'),
      ];
      ClasspathResources.registerAll({
        'i18n/embedded.properties': const EmbeddedResource.text('e=1'),
      }, owner: 'resource_fixes_test');
    });
    tearDown(() {
      for (final remove in removals) {
        remove();
      }
      ClasspathResources.registerAll(const {}, owner: 'resource_fixes_test');
    });

    List<String> contents(String pattern) => [
      for (final resource in PathMatchingResourcePatternResolver().getResources(
        pattern,
      ))
        resource.readAsStringSync(),
    ];

    test('classpath: searches the first root with the base directory', () {
      expect(contents('classpath:i18n/*.properties'), ['a=2']);
      expect(contents('classpath:other/*.properties'), ['c=2']);
      expect(contents('classpath:/i18n/**/*.properties'), ['a=2']);
    });

    test('classpath*: searches every root, embedded resources too', () {
      expect(contents('classpath*:i18n/**/*.properties'), [
        'a=2',
        'a=1',
        'b=1',
        'e=1',
      ]);
      expect(contents('classpath*:i18n/a.properties'), ['a=2', 'a=1']);
      expect(contents('classpath*:/i18n/embedded.properties'), ['e=1']);
      expect(contents('classpath*:i18n/none.properties'), isEmpty);
    });
  });

  group('file patterns', () {
    test('matching directories are returned, others are not walked', () {
      write('config/a.properties', 'a');
      write('config/sub/b.properties', 'b');
      write('config/deep/x/y/c.txt', 'c');
      final resolver = PathMatchingResourcePatternResolver();
      expect(
        [
          for (final r in resolver.getResources('file:${temp.path}/config/*'))
            r.filename,
        ],
        ['a.properties', 'deep', 'sub'],
      );
      expect(
        resolver.getResources('file:${temp.path}/config/*/b.properties'),
        hasLength(1),
      );
    });

    test('file: URLs are percent-decoded', () {
      final file = write('my dir/a.properties', 'a=1');
      final loader = DefaultResourceLoader();
      final encoded = 'file://${temp.path}/my%20dir/a.properties';
      expect(loader.getResource(encoded).readAsStringSync(), 'a=1');
      expect(FileSystemResource.fromFileUrl('file:100%.txt').path, '100%.txt');
      expect(
        PathMatchingResourcePatternResolver().getResources(
          'file:${temp.path}/my%20dir/*.properties',
        ),
        [FileSystemResource(file.path)],
      );
    });

    // Spring looks for wildcards in the location as written and decodes
    // only the root directory (its URL's file): an escaped `*` expanded to
    // every name here.
    test('file: wildcards are looked for before percent-decoding', () {
      write('mail/a.txt', 'a');
      write('mail/b.txt', 'b');
      final resolver = PathMatchingResourcePatternResolver();
      final base = temp.path.replaceAll(r'\', '/');
      expect(resolver.getResources('file:$base/mail/%2A.txt'), isEmpty);
      expect(resolver.getResources('file:$base/mail/a%3F.txt'), isEmpty);
      write('mail/a%41.txt', 'escaped');
      expect(
        [
          for (final r in resolver.getResources('file:$base/mail/*%41.txt'))
            r.filename,
        ],
        ['a%41.txt'],
      );
      if (!Platform.isWindows) {
        final literal = write('mail/*.txt', 'literal');
        expect(resolver.getResources('file:$base/mail/%2A.txt'), [
          FileSystemResource(literal.path),
        ]);
      }
    });
  });

  test('FileSystemResource directories exist but are not readable', () {
    write('dir/a.txt', 'a');
    final directory = FileSystemResource('${temp.path}/dir');
    expect(directory.exists(), isTrue);
    expect(directory.isReadable, isFalse);
    expect(directory.isDirectory, isTrue);
    expect(FileSystemResource('${temp.path}/dir/a.txt').isReadable, isTrue);
    expect(FileSystemResource('${temp.path}/none').exists(), isFalse);
  });

  test('extractUriTemplateVariables backtracks over **', () {
    final matcher = AntPathMatcher();
    expect(matcher.extractUriTemplateVariables('/**/{a}/x/**', '/p/q/x/s'), {
      'a': 'q',
    });
    expect(
      matcher.extractUriTemplateVariables(
        '/**/{a}/{b}/x/**/{c}',
        '/p/q/r/x/s/t',
      ),
      {'a': 'q', 'b': 'r', 'c': 't'},
    );
  });

  group('placeholders', () {
    final helper = PropertyPlaceholderHelper();
    final values = {'b': 'B', 'db:url': 'jdbc', 'db': 'x'};

    test('an unclosed prefix is text; later placeholders still resolve', () {
      expect(
        helper.replacePlaceholders(r'${a ${b}', (k) => values[k]),
        r'${a B',
      );
      expect(helper.replacePlaceholders(r'x ${a', (k) => values[k]), r'x ${a');
    });

    test('key:default is first tried as a key', () {
      expect(
        helper.replacePlaceholders(r'${db:url}', (k) => values[k]),
        'jdbc',
      );
      expect(helper.replacePlaceholders(r'${db:other}', (k) => values[k]), 'x');
      expect(
        helper.replacePlaceholders(r'${no:fallback}', (k) => values[k]),
        'fallback',
      );
    });
  });
}
