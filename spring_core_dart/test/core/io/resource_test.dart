import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

class _AsyncOnly extends AbstractResource {
  const _AsyncOnly();
  @override
  String get description => 'async only';
  @override
  bool exists() => true;
  @override
  Future<Uint8List> readAsBytes() async =>
      Uint8List.fromList(utf8.encode('a=1'));
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('scd_io_'));
  tearDown(() => temp.deleteSync(recursive: true));

  File write(String path, String content) => File('${temp.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  group('ByteArrayResource', () {
    test('reads sync and async, copies bytes', () async {
      final bytes = Uint8List.fromList([104, 105]);
      final resource = ByteArrayResource(bytes, description: 'hi');
      bytes[0] = 0;
      expect(resource.exists(), isTrue);
      expect(resource.isReadable, isTrue);
      expect(resource.supportsSyncRead, isTrue);
      expect(resource.readAsStringSync(), 'hi');
      expect(await resource.readAsString(), 'hi');
      expect(await resource.readAsBytes(), [104, 105]);
      expect(resource.filename, isNull);
      expect(resource.uri, isNull);
      expect(resource.toString(), 'hi');
      expect(
        () => resource.createRelative('x'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('fromString and equality', () {
      final a = ByteArrayResource.fromString('héllo');
      expect(a.readAsStringSync(), 'héllo');
      expect(a.description, 'Byte array resource');
      expect(a, ByteArrayResource.fromString('héllo'));
      expect(a == ByteArrayResource.fromString('hello'), isFalse);
      expect(a == ByteArrayResource.fromString('héll'), isFalse);
      expect(a.hashCode, ByteArrayResource.fromString('héllo').hashCode);
    });
  });

  test('DescriptiveResource never exists', () async {
    const resource = DescriptiveResource('nothing');
    expect(resource.exists(), isFalse);
    expect(resource.isReadable, isFalse);
    expect(resource.supportsSyncRead, isFalse);
    expect(() => resource.readAsBytesSync(), throwsUnsupportedError);
    await expectLater(resource.readAsBytes(), throwsStateError);
    expect(resource, const DescriptiveResource('nothing'));
    expect(resource.hashCode, const DescriptiveResource('nothing').hashCode);
  });

  test('async-only resources decode through AbstractResource', () async {
    const resource = _AsyncOnly();
    expect(await resource.readAsString(), 'a=1');
    expect(() => resource.readAsStringSync(), throwsUnsupportedError);
  });

  group('FileSystemResource', () {
    test('reads files and metadata', () async {
      final file = write('dir/app.properties', 'x=1');
      final resource = FileSystemResource(file.path);
      expect(resource.exists(), isTrue);
      expect(resource.supportsSyncRead, isTrue);
      expect(resource.filename, 'app.properties');
      expect(resource.readAsStringSync(), 'x=1');
      expect(await resource.readAsString(), 'x=1');
      expect(resource.contentLength(), 3);
      expect(resource.lastModified(), isA<DateTime>());
      expect(resource.description, startsWith('file ['));
      expect(resource.uri.scheme, 'file');
    });

    test('paths are normalized', () {
      expect(FileSystemResource('a/./b/../c').path, 'a/c');
      expect(FileSystemResource(r'a\b').path, 'a/b');
      expect(FileSystemResource('/x/../y').path, '/y');
      expect(FileSystemResource('../up').path, '../up');
      expect(FileSystemResource('./').path, '.');
      // `..` cannot climb above the root.
      expect(FileSystemResource('/../etc/x').path, '/etc/x');
      expect(FileSystemResource('/..').path, '/');
      expect(FileSystemResource(r'C:\..\cfg\a').path, 'C:/cfg/a');
      expect(FileSystemResource('C:/a/../../b').path, 'C:/b');
      expect(FileSystemResource('a/b'), FileSystemResource('a/./b'));
      expect(
        FileSystemResource('a').hashCode,
        FileSystemResource('a').hashCode,
      );
    });

    test('createRelative', () {
      expect(
        FileSystemResource('/a/b.txt').createRelative('c.txt').path,
        '/a/c.txt',
      );
      expect(FileSystemResource('b.txt').createRelative('c.txt').path, 'c.txt');
    });

    test('missing file', () {
      expect(FileSystemResource('${temp.path}/none').exists(), isFalse);
    });
  });

  group('DefaultResourceLoader', () {
    test('file prefixes and plain paths', () {
      final file = write('a.txt', 'A');
      final loader = DefaultResourceLoader();
      expect(loader.getResource('file:${file.path}').readAsStringSync(), 'A');
      expect(loader.getResource('file://${file.path}').exists(), isTrue);
      expect(loader.getResource(file.path).exists(), isTrue);
      expect(loader.getResource(r'C:\windows\path'), isA<FileSystemResource>());
    });

    test('unknown protocol does not exist', () {
      final resource = DefaultResourceLoader().getResource('classpath:x');
      expect(resource.exists(), isFalse);
      expect(resource.description, contains('unsupported protocol'));
    });

    test('protocol resolvers come first', () {
      final memory = InMemoryProtocolResolver('memory:', {
        'cfg/a.properties': 'a=1',
      });
      final loader = DefaultResourceLoader(protocolResolvers: [memory])
        ..addProtocolResolver(
          FunctionProtocolResolver(
            (location, _) => location == 'magic:'
                ? ByteArrayResource.fromString('magic')
                : null,
          ),
        );
      expect(loader.protocolResolvers, hasLength(2));
      expect(
        loader.getResource('memory:cfg/a.properties').readAsStringSync(),
        'a=1',
      );
      expect(loader.getResource('memory:/cfg/./a.properties').exists(), isTrue);
      expect(loader.getResource('memory:none').exists(), isFalse);
      memory.put('late', 'x');
      expect(loader.getResource('memory:late').exists(), isTrue);
      expect(loader.getResource('magic:').readAsStringSync(), 'magic');
    });
  });

  group('PathMatchingResourcePatternResolver', () {
    test('expands file patterns', () {
      write('config/a.properties', 'a');
      write('config/sub/b.properties', 'b');
      write('config/sub/c.txt', 'c');
      final resolver = PathMatchingResourcePatternResolver();
      List<String> names(String pattern) => [
        for (final r in resolver.getResources(pattern)) r.filename!,
      ];
      expect(names('file:${temp.path}/config/**/*.properties'), [
        'a.properties',
        'b.properties',
      ]);
      expect(names('${temp.path}/config/*.properties'), ['a.properties']);
      expect(
        names('${temp.path}/config/sub/*'),
        ['c.txt', 'b.properties']..sort(),
      );
      expect(names('${temp.path}/missing/*.properties'), isEmpty);
    });

    test('relative patterns', () {
      write('rel/x.properties', 'x');
      final previous = Directory.current;
      Directory.current = temp;
      try {
        final resolver = PathMatchingResourcePatternResolver();
        expect(resolver.getResources('rel/*.properties'), hasLength(1));
        expect(resolver.getResources('*/x.properties'), hasLength(1));
      } finally {
        Directory.current = previous;
      }
    });

    test('plain locations and other protocols', () {
      final file = write('one.txt', '1');
      final resolver = PathMatchingResourcePatternResolver(
        resourceLoader: DefaultResourceLoader(
          protocolResolvers: [
            InMemoryProtocolResolver('mem:', {'a': '1'}),
          ],
        ),
      );
      expect(resolver.getResources(file.path), hasLength(1));
      expect(resolver.getResources('${temp.path}/none.txt'), isEmpty);
      expect(resolver.getResources('mem:a'), hasLength(1));
      expect(resolver.getResources('mem:*'), isEmpty);
      expect(resolver.getResource('mem:a').exists(), isTrue);
    });
  });

  group('PropertiesParser', () {
    test('separators, comments, blank lines', () {
      expect(
        PropertiesParser.parse('''
# comment
! another
a=1
b : 2
c 3
d=
e
  f = spaced value  
g	tab
h = = x
'''),
        {
          'a': '1',
          'b': '2',
          'c': '3',
          'd': '',
          'e': '',
          'f': 'spaced value  ',
          'g': 'tab',
          'h': '= x',
        },
      );
    });

    test('continuations, escapes, unicode, escaped separators', () {
      expect(
        PropertiesParser.parse(
          'multi = one, \\\n'
          '        two, \\\n'
          '        three\n'
          'esc = tab\\there\\nnl\\rcr\\ff\\\\back\n'
          'uni = \\u0041\\u00e9\n'
          'key\\=with\\:sep\\ space = v\n'
          'plain\\q = other\n'
          'trailing = end\\\n',
        ),
        {
          'multi': 'one, two, three',
          'esc': 'tab\there\nnl\rcr\ff\\back',
          'uni': 'Aé',
          'key=with:sep space': 'v',
          'plainq': 'other',
          'trailing': 'end',
        },
      );
    });

    test('even backslashes do not continue, last key wins, CRLF', () {
      expect(PropertiesParser.parse('a = x\\\\\r\nb = 1\r\nb = 2\rc=3'), {
        'a': r'x\',
        'b': '2',
        'c': '3',
      });
    });

    test('malformed unicode escape', () {
      expect(() => PropertiesParser.parse(r'a = \u12'), throwsFormatException);
      expect(
        () => PropertiesParser.parse(r'a = \uZZZZ'),
        throwsFormatException,
      );
    });

    test('loader utils', () async {
      final resource = ByteArrayResource.fromString('a=1');
      expect(PropertiesLoaderUtils.loadPropertiesSync(resource), {'a': '1'});
      expect(await PropertiesLoaderUtils.loadProperties(resource), {'a': '1'});
    });
  });

  group('ResourcePropertySource', () {
    test('sync, async and from content', () async {
      final resource = ByteArrayResource.fromString('a=1', description: 'res');
      final sync = ResourcePropertySource.fromResource(resource);
      expect(sync.name, 'res');
      expect(sync.getProperty('a'), '1');
      final named = await ResourcePropertySource.load(resource, name: 'n');
      expect(named.name, 'n');
      expect(named.getProperty('a'), '1');
      expect(
        ResourcePropertySource.fromContent(resource, 'b=2').getProperty('b'),
        '2',
      );
    });
  });
}
