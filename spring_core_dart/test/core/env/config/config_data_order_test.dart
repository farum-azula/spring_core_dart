import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:test/test.dart';

// Which of the places a config file is listed at counts, and in which
// order profile variants of imports land: Spring Boot 4.1.2's contributor
// tree (ConfigDataImporter reads a list from its last location and skips a
// resource read before; ConfigDataEnvironmentContributor.moveProfileSpecific
// moves the variants of imports up). Every expectation was checked with a
// Spring Boot 4.1.2 run of the same files.
void main() {
  late Directory temp;
  late String root;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('scd_config_order_');
    root = temp.path.replaceAll(r'\', '/');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  void write(String path, String content) => File('$root/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(content);

  StandardEnvironment process(
    Map<String, Object?> props, {
    List<String>? defaultLocations,
  }) {
    final environment = StandardEnvironment(systemEnvironment: {})
      ..propertySources.addFirst(MapPropertySource('cli', props));
    ConfigDataEnvironment(
      environment,
      defaultLocations: defaultLocations ?? ['optional:file:$root/'],
    ).processAndApplySync();
    return environment;
  }

  group('a file listed twice counts at its later, stronger place', () {
    setUp(() {
      write('x.properties', 'b=x\n');
      write('y.properties', 'b=y\n');
    });

    test("in a file's spring.config.import, comma list or YAML list", () {
      write(
        'application.properties',
        'spring.config.import=x.properties,y.properties,x.properties\n',
      );
      expect(process({}).getProperty('b'), 'x');
      write(
        'application.properties',
        'spring.config.import=y.properties,x.properties,y.properties\n',
      );
      expect(process({}).getProperty('b'), 'y');
      write(
        'application.properties',
        'spring.config.import[0]=x.properties\n'
            'spring.config.import[1]=y.properties\n'
            'spring.config.import[2]=x.properties\n',
      );
      expect(process({}).getProperty('b'), 'x');
    });

    test('in spring.config.location, a command-line import and '
        'additional-location', () {
      final list =
          'file:$root/x.properties,file:$root/y.properties,'
          'file:$root/x.properties';
      for (final key in [
        'spring.config.location',
        'spring.config.import',
        'spring.config.additional-location',
      ]) {
        expect(process({key: list}).getProperty('b'), 'x', reason: key);
      }
    });

    test('a directory, and a directory imported again by a file', () {
      write('d1/application.properties', 'b=d1\n');
      write('d2/application.properties', 'b=d2\n');
      expect(
        process({
          'spring.config.location':
              'file:$root/d1/,file:$root/d2/,file:$root/d1/',
        }).getProperty('b'),
        'd1',
      );
      write('d/application.properties', 'b=d\n');
      write(
        'application.properties',
        'spring.config.import=d/,x.properties,d/',
      );
      expect(process({}).getProperty('b'), 'd');
    });

    test('an additional location that is a default one goes on top', () {
      // `./config/` is a default location; named again as an additional
      // location it wins over `./config/*/`, as in Boot.
      write('config/application.properties', 'b=config\n');
      write('config/eu/application.properties', 'b=eu\n');
      const group =
          'optional:file:{root}/;optional:file:{root}/config/;'
          'optional:file:{root}/config/*/';
      final locations = [group.replaceAll('{root}', root)];
      expect(
        process({}, defaultLocations: locations).getProperty('b'),
        'eu',
      );
      expect(
        process({
          'spring.config.additional-location': 'file:$root/config/',
        }, defaultLocations: locations).getProperty('b'),
        'config',
      );
      // A file of an earlier location named as an additional one too.
      write('application.properties', 'b=root\n');
      for (final additional in [
        'file:$root/',
        'file:$root/application.properties',
      ]) {
        expect(
          process(
            {'spring.config.additional-location': additional},
            defaultLocations: [
              'optional:file:$root/',
              'optional:file:$root/config/',
            ],
          ).getProperty('b'),
          'root',
          reason: additional,
        );
      }
    });

    test('the encoding hint of the occurrence that counts applies', () {
      File('$root/x.properties').writeAsBytesSync(utf8.encode('b=café\n'));
      write('y.properties', 'c=y\n');
      write(
        'application.properties',
        'spring.config.import=x.properties[encoding=utf-8],y.properties,'
            'x.properties[encoding=iso-8859-1]\n',
      );
      expect(process({}).getProperty('b'), 'cafÃ©');
      write(
        'application.properties',
        'spring.config.import=x.properties[encoding=iso-8859-1],'
            'x.properties[encoding=utf-8]\n',
      );
      expect(process({}).getProperty('b'), 'café');
    });

    // The occurrence skipped for one read before was decoded first, with
    // its own hint (or UTF-8), and failed the start ("not valid UTF-8")
    // where Boot skips a loaded resource without reading it. Checked with a
    // synchronous pass, an asynchronous one and one over resources read
    // only asynchronously (`async:`, as Flutter assets and `http:` files
    // are); `{base}` is `file:<root>` or `async:`.
    group('a skipped occurrence is not read, so its encoding hint '
        '(or none) cannot fail the start', () {
      Future<List<StandardEnvironment>> threeWays(
        Map<String, String> props,
      ) async {
        final files = DefaultResourceLoader(
          protocolResolvers: [
            FunctionProtocolResolver(
              (location, _) => location.startsWith('async:')
                  ? _AsyncFile(File('$root${location.substring(6)}'))
                  : null,
            ),
          ],
        );
        final runs = <StandardEnvironment>[];
        for (final (base, async) in [
          ('file:$root', false),
          ('file:$root', true),
          ('async:', true),
        ]) {
          final environment = StandardEnvironment(systemEnvironment: {})
            ..propertySources.addFirst(
              MapPropertySource('cli', {
                for (final MapEntry(:key, :value) in props.entries)
                  key: value.replaceAll('{base}', base),
              }),
            );
          final config = ConfigDataEnvironment(
            environment,
            resourceLoader: files,
            defaultLocations: ['optional:$base/'],
          );
          if (async) {
            await config.processAndApply();
          } else {
            config.processAndApplySync();
          }
          runs.add(environment);
        }
        return runs;
      }

      setUp(
        () => File(
          '$root/legacy.properties',
        ).writeAsBytesSync([...'a=caf'.codeUnits, 0xe9, 0x0a]),
      );

      test('a location list naming the file twice', () async {
        for (final props in [
          {
            'spring.config.location':
                '{base}/legacy.properties[encoding=utf8],'
                '{base}/legacy.properties[encoding=latin1]',
          },
          {
            'spring.config.location': '{base}/legacy.properties[encoding=utf8]',
            'spring.config.import': '{base}/legacy.properties[encoding=latin1]',
          },
        ]) {
          for (final e in await threeWays(props)) {
            expect(e.getProperty('a'), 'café', reason: '$props');
          }
        }
      });

      test('an imported file importing it again', () async {
        // legacy.properties, the later item, is read first, with its hint;
        // b.properties' import of it is a repeat.
        write(
          'application.properties',
          'c=base\n'
              'spring.config.import=b.properties,'
              'legacy.properties[encoding=iso-8859-1]\n',
        );
        write(
          'b.properties',
          'b=fromb\nspring.config.import=legacy.properties\n',
        );
        for (final e in await threeWays({})) {
          expect(
            [e.getProperty('a'), e.getProperty('b'), e.getProperty('c')],
            ['café', 'fromb', 'base'],
          );
        }
      });

      test('a profile file importing it again', () async {
        write(
          'application.properties',
          'c=base\n'
              'spring.config.import=legacy.properties[encoding=iso-8859-1]\n',
        );
        write(
          'application-dev.properties',
          'b=dev\nspring.config.import=legacy.properties\n',
        );
        for (final e in await threeWays({'spring.profiles.active': 'dev'})) {
          expect(
            [e.getProperty('a'), e.getProperty('b'), e.getProperty('c')],
            ['café', 'dev', 'base'],
          );
        }
      });
    });

    test('in a ; group, a repeat of the same text counts at its first '
        'place (one reference, as in Boot), another spelling at its last', () {
      expect(
        process({
          'spring.config.location':
              'file:$root/x.properties;file:$root/y.properties;'
              'file:$root/x.properties',
        }).getProperty('b'),
        'y',
      );
      expect(
        process({
          'spring.config.location':
              'file:$root/x.properties;file:$root/y.properties;'
              'file:$root/./x.properties',
        }).getProperty('b'),
        'x',
      );
    });

    test('each additional location is read with its imports before the '
        'next one; a command-line import list is read at once', () {
      write('a.properties', 'b=a\n');
      write('b.properties', 'b=b\nspring.config.import=a.properties\n');
      final list = 'file:$root/a.properties,file:$root/b.properties';
      // b.properties is read first and imports a.properties above itself.
      expect(
        process({
          'spring.config.additional-location': list,
        }).getProperty('b'),
        'a',
      );
      // Both are read together; b.properties' import of a is a repeat.
      expect(process({'spring.config.import': list}).getProperty('b'), 'b');
    });
  });

  group('the profile variants of imports move up as in Boot', () {
    test('x-dev, for an import of application.properties, wins over '
        'application-dev', () {
      write(
        'application.properties',
        'b=app\nspring.config.import=x.properties\n',
      );
      write('application-dev.properties', 'b=app-dev\n');
      write('x.properties', 'c=x\n');
      write('x-dev.properties', 'b=x-dev\n');
      final e = process({'spring.profiles.active': 'dev'});
      expect(e.getProperty('b'), 'x-dev');
      expect(e.getProperty('c'), 'x');
    });

    test('so does the variant of an import of an on-profile document', () {
      write(
        'application.properties',
        'b=app\n#---\nspring.config.activate.on-profile=dev\n'
            'spring.config.import=a.properties,b.properties\n',
      );
      write('a.properties', 'b=a\nc=a\n');
      write('a-dev.properties', 'b=a-dev\n');
      write('b.properties', 'b=b\nc=b\n');
      write('application-dev.properties', 'b=app-dev\nc=app-dev\n');
      final e = process({'spring.profiles.active': 'dev'});
      expect(e.getProperty('b'), 'a-dev');
      expect(e.getProperty('c'), 'app-dev');
    });

    test('a command-line import list: every variant above every plain '
        'file; each additional location: its variants above its file', () {
      write('g1.properties', 'b=g1\n');
      write('g1-dev.properties', 'b=g1-dev\n');
      write('g2.properties', 'b=g2\n');
      final list = 'file:$root/g1.properties,file:$root/g2.properties';
      expect(
        process({
          'spring.profiles.active': 'dev',
          'spring.config.import': list,
        }).getProperty('b'),
        'g1-dev',
      );
      expect(
        process({
          'spring.profiles.active': 'dev',
          'spring.config.additional-location': list,
        }).getProperty('b'),
        'g2',
      );
    });
  });
}

// A file that can only be read asynchronously, as a Flutter asset is.
final class _AsyncFile extends AbstractResource {
  _AsyncFile(this.file);

  final File file;

  @override
  String get description => 'async file [${file.path}]';

  @override
  bool exists() => file.existsSync();

  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();
}
