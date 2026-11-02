// The theme from a URL: download, the cache across restarts, refresh with
// conditional requests, the pin, keys that are not a theme's, offline, the
// github: shorthand, the name the app chooses, extends on top. A fake HTTP
// transport plays the server; "a restart" is a new SpringThemes and loader
// over the same files.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_auto_configuration.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/files/sha256.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_source.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

const _url = 'https://raw.githubusercontent.com/neon/themes/main/ocean.yml';

const _ocean = '''
spring:
  flutter:
    theme:
      themes:
        ocean:
          seed-color: '#FF0000'
''';

const _oceanBlue = '''
spring:
  flutter:
    theme:
      themes:
        whatever:
          seed-color: '#0000FF'
''';

class _Server implements HttpTransport {
  final requests = <HttpRequest>[];
  FutureOr<HttpResponse> Function(HttpRequest request) handler = (r) =>
      HttpResponse(404, request: r);
  bool closed = false;

  @override
  Future<HttpResponse> send(HttpRequest request) async => handler(request);

  @override
  Future<StreamedHttpResponse> stream(HttpRequest request) async {
    requests.add(request);
    final response = await handler(request);
    return StreamedHttpResponse(
      response.statusCode,
      headers: response.headers,
      body: Stream.value(response.bodyBytes),
      request: request,
    );
  }

  @override
  void close() => closed = true;
}

HttpResponse _ok(String body, {String? etag, String? lastModified}) =>
    HttpResponse(
      200,
      body: utf8.encode(body),
      headers: HttpHeaders({'ETag': ?etag, 'Last-Modified': ?lastModified}),
    );

Color _primary(SpringThemes themes, String name) =>
    themes.material(name).colorScheme.primary;

void main() {
  late InMemoryFileStore store;
  late FileTemplate files;
  late _Server server;
  var now = DateTime.utc(2026, 11, 2, 12);

  setUp(() {
    store = InMemoryFileStore(clock: () => now);
    files = FileTemplate(store);
    server = _Server();
    now = DateTime.utc(2026, 11, 2, 12);
  });

  // A start of the app: new themes, a new loader, the same files.
  Future<(SpringThemes, ThemeSourceLoader)> start(
    Map<String, String> properties, {
    _Server? over,
    Duration timeout = const Duration(seconds: 5),
    int maxBytes = ThemeSourceLoader.defaultMaxBytes,
  }) async {
    final themes = SpringThemes(properties);
    final loader = ThemeSourceLoader(
      themes: themes,
      files: files,
      sources: ThemeSource.read(properties, themes),
      transport: over ?? server,
      timeout: timeout,
      maxBytes: maxBytes,
      clock: () => now,
    );
    await loader.run(ApplicationArguments(const []));
    return (themes, loader);
  }

  final once = {
    'active': 'ocean',
    'themes.ocean.source': _url,
    'themes.ocean.seed-color': '#00FF00',
  };

  autoConfigurationTests();

  group('the source', () {
    test('https URLs and github: shorthand', () {
      expect(
        ThemeSource.parseUri('github:neon/themes/dir/ocean.yml@v3').toString(),
        'https://raw.githubusercontent.com/neon/themes/v3/dir/ocean.yml',
      );
      expect(
        ThemeSource.parseUri('github:neon/themes/ocean.yml').toString(),
        'https://raw.githubusercontent.com/neon/themes/HEAD/ocean.yml',
      );
      expect(ThemeSource.parseUri(_url).toString(), _url);
      for (final bad in [
        'http://example.com/t.yml',
        'file:///etc/passwd',
        'ftp://x/t.yml',
        '/relative.yml',
        'github:only/two',
        'github:a/b/c@',
      ]) {
        expect(
          () => ThemeSource.parseUri(bad),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('invalid keys name the property', () {
      final themes = SpringThemes(const {});
      expect(
        () => ThemeSource.read(const {
          'themes.a.source': 'http://x/t.yml',
        }, themes),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.name,
            'name',
            'spring.flutter.theme.themes.a.source',
          ),
        ),
      );
      expect(
        () => ThemeSource.read({
          'themes.a.source': _url,
          'themes.a.source-sha256': 'abc',
        }, themes),
        throwsArgumentError,
      );
    });

    test('the source keys are not theme keys', () async {
      // No download: the theme exists with the app's own values.
      final themes = SpringThemes({
        'themes.ocean.source': _url,
        'themes.ocean.source-sha256': 'x' * 64,
        'themes.ocean.refresh': '1h',
        'themes.ocean.seed-color': '#00FF00',
      });
      expect(themes.names, contains('ocean'));
      expect(_primary(themes, 'ocean'), isNotNull);
    });
  });

  group('without refresh', () {
    test(
      'the first start downloads and caches; later starts do not ask',
      () async {
        server.handler = (_) => _ok(_ocean);
        var (themes, _) = await start(once);
        expect(server.requests, hasLength(1));
        expect(server.requests.single.url.toString(), _url);
        expect(
          _primary(themes, 'ocean'),
          isNot(_primary(SpringThemes(once), 'ocean')),
        );
        final bundled = _primary(SpringThemes(const {}), 'light');
        expect(_primary(themes, 'ocean'), isNot(bundled));

        final key = ThemeSource.read(once, themes).single.cacheKey;
        expect(
          await files.read<String>('spring/themes/$key/theme.yml'),
          _ocean,
        );
        final meta = jsonDecode(
          (await files.read<String>('spring/themes/$key/meta.json'))!,
        ) as Map;
        expect(meta['source'], _url);
        expect(meta['sha256'], sha256HexOfString(_ocean));
        expect(meta['fetchedAt'], '2026-11-02T12:00:00.000Z');

        // Restarts, a year later, the network gone: the cache, no request.
        now = now.add(const Duration(days: 365));
        server.requests.clear();
        final offline = _Server()
          ..handler = (_) => throw HttpTransportException('offline');
        for (var i = 0; i < 3; i++) {
          final (again, loader) = await start(once, over: offline);
          await loader.idle;
          expect(_primary(again, 'ocean'), _primary(themes, 'ocean'));
        }
        expect(offline.requests, isEmpty);
      },
    );

    test(
      'the theme is shown under the app\'s name, whatever the file calls it',
      () async {
        server.handler = (_) => _ok(_oceanBlue);
        final (themes, _) = await start(once);
        expect(themes.names, containsAll(['light', 'dark', 'ocean']));
        expect(themes.names, isNot(contains('whatever')));
        final blue = ColorScheme.fromSeed(seedColor: const Color(0xFF0000FF));
        expect(_primary(themes, 'ocean'), blue.primary);
      },
    );

    test(
      'a file with the theme\'s keys at the top, or under spring.flutter.theme',
      () async {
        server.handler = (_) => _ok("seed-color: '#0000FF'\n");
        var (themes, _) = await start(once);
        final blue = ColorScheme.fromSeed(seedColor: const Color(0xFF0000FF));
        expect(_primary(themes, 'ocean'), blue.primary);

        files = FileTemplate(InMemoryFileStore());
        server.handler = (_) => _ok(
          "spring.flutter.theme.seed-color: '#0000FF'\n",
        );
        (themes, _) = await start(once);
        expect(_primary(themes, 'ocean'), blue.primary);
      },
    );

    test(
      'a changed source or pin downloads again and drops the old cache',
      () async {
        server.handler = (_) => _ok(_ocean);
        var (themes, _) = await start(once);
        final oldKey = ThemeSource.read(once, themes).single.cacheKey;

        server.handler = (_) => _ok(_oceanBlue);
        final moved = {...once, 'themes.ocean.source': '$_url?v=2'};
        (themes, _) = await start(moved);
        expect(server.requests, hasLength(2));
        expect(await files.list('spring/themes/$oldKey/'), isEmpty);
        final blue = ColorScheme.fromSeed(seedColor: const Color(0xFF0000FF));
        expect(_primary(themes, 'ocean'), blue.primary);

        final digest = sha256HexOfString(_oceanBlue);
        final pinned = {...moved, 'themes.ocean.source-sha256': digest};
        (themes, _) = await start(pinned);
        expect(server.requests, hasLength(3));
        (themes, _) = await start(pinned);
        expect(server.requests, hasLength(3));
      },
    );

    test(
      'caches of sources no longer configured are removed at start',
      () async {
        server.handler = (_) => _ok(_ocean);
        await start(once);
        expect(await files.list('spring/themes/'), isNotEmpty);
        await files.write('spring/themes/stale/theme.yml', 'x');
        await files.write('spring/other.txt', 'kept');
        await start(const {});
        await pumpEventQueue();
        expect(await files.list('spring/themes/'), isEmpty);
        expect(await files.read<String>('spring/other.txt'), 'kept');
      },
    );
  });

  group('the pin', () {
    test(
      'content with another sha256 is refused, not cached or shown',
      () async {
        server.handler = (_) => _ok(_ocean);
        final pinned = {...once, 'themes.ocean.source-sha256': 'a' * 64};
        final (themes, _) = await start(pinned);
        expect(server.requests, hasLength(1));
        expect(await files.list('spring/themes/'), isEmpty);
        expect(
          _primary(themes, 'ocean'),
          _primary(SpringThemes(pinned), 'ocean'),
        );
      },
    );

    test('the right sha256 is accepted', () async {
      server.handler = (_) => _ok(_oceanBlue);
      final pinned = {
        ...once,
        'themes.ocean.source-sha256': sha256HexOfString(_oceanBlue)
            .toUpperCase(),
      };
      final (themes, _) = await start(pinned);
      final blue = ColorScheme.fromSeed(seedColor: const Color(0xFF0000FF));
      expect(_primary(themes, 'ocean'), blue.primary);
    });

    test('a cache that no longer matches its digest is ignored', () async {
      server.handler = (_) => _ok(_ocean);
      final (themes, _) = await start(once);
      final key = ThemeSource.read(once, themes).single.cacheKey;
      await files.write('spring/themes/$key/theme.yml', 'seed-color: red');
      await start(once);
      expect(server.requests, hasLength(2));
    });
  });

  group('refresh', () {
    final refreshing = {...once, 'themes.ocean.refresh': '1h'};

    test(
      'a fresh cache is used at once, with no request until it is old',
      () async {
        server.handler = (_) => _ok(_ocean, etag: '"v1"');
        var (themes, loader) = await start(refreshing);
        expect(server.requests, hasLength(1));
        loader.dispose();

        now = now.add(const Duration(minutes: 30));
        (themes, loader) = await start(refreshing);
        await loader.idle;
        expect(server.requests, hasLength(1));
        loader.dispose();
      },
    );

    test(
      'an old cache is shown at once and read again with If-None-Match: 304',
      () async {
        server.handler = (_) => _ok(
          _ocean,
          etag: '"v1"',
          lastModified: 'Mon, 02 Nov 2026 10:00:00 GMT',
        );
        var (themes, loader) = await start(refreshing);
        loader.dispose();

        now = now.add(const Duration(hours: 2));
        final slow = Completer<HttpResponse>();
        final lateServer = _Server()..handler = (_) => slow.future;
        (themes, loader) = await start(refreshing, over: lateServer);
        // The start did not wait for the network: the theme is the cached one.
        await pumpEventQueue();
        expect(lateServer.requests, hasLength(1));
        final request = lateServer.requests.single;
        expect(request.headers['If-None-Match'], '"v1"');
        expect(
          request.headers['If-Modified-Since'],
          'Mon, 02 Nov 2026 10:00:00 GMT',
        );
        final red = ColorScheme.fromSeed(seedColor: const Color(0xFFFF0000));
        expect(_primary(themes, 'ocean'), red.primary);

        slow.complete(HttpResponse(304));
        await loader.idle;
        expect(_primary(themes, 'ocean'), red.primary);
        final key = ThemeSource.read(refreshing, themes).single.cacheKey;
        final meta = jsonDecode(
          (await files.read<String>('spring/themes/$key/meta.json'))!,
        ) as Map;
        expect(meta['fetchedAt'], '2026-11-02T14:00:00.000Z');
        expect(meta['etag'], '"v1"');
        loader.dispose();
      },
    );

    test('new content is applied live after the background refresh', () async {
      server.handler = (_) => _ok(_ocean, etag: '"v1"');
      var (themes, loader) = await start(refreshing);
      loader.dispose();

      now = now.add(const Duration(hours: 3));
      server.handler = (_) => _ok(_oceanBlue, etag: '"v2"');
      (themes, loader) = await start(refreshing);
      var notified = 0;
      themes.addListener(() => notified++);
      final selection = ThemeSelection(themes);
      expect(selection.active, 'ocean');
      await loader.idle;
      expect(notified, greaterThan(0));
      final blue = ColorScheme.fromSeed(seedColor: const Color(0xFF0000FF));
      expect(_primary(themes, 'ocean'), blue.primary);
      // And it is the cache now.
      server.requests.clear();
      final (again, other) = await start(refreshing);
      expect(_primary(again, 'ocean'), blue.primary);
      expect(server.requests, isEmpty);
      other.dispose();
      loader.dispose();
    });

    test('an error on refresh keeps the cache shown', () async {
      server.handler = (_) => _ok(_ocean);
      var (themes, loader) = await start(refreshing);
      loader.dispose();
      now = now.add(const Duration(hours: 3));
      server.handler = (_) => throw HttpTransportException('down');
      (themes, loader) = await start(refreshing);
      await loader.idle;
      final red = ColorScheme.fromSeed(seedColor: const Color(0xFFFF0000));
      expect(_primary(themes, 'ocean'), red.primary);
      loader.dispose();
    });

    test(
      'dispose cancels what is waiting and closes only its own client',
      () async {
        server.handler = (_) => _ok(_ocean);
        final (_, loader) = await start(refreshing);
        loader.dispose();
        expect(server.closed, isFalse);
      },
    );
  });

  group('failures start the app all the same', () {
    test(
      'offline on the first start: the theme of the app\'s resources',
      () async {
        server.handler = (_) => throw HttpTransportException('no network');
        final (themes, _) = await start(once);
        expect(
          _primary(themes, 'ocean'),
          _primary(SpringThemes(once), 'ocean'),
        );
        expect(await files.list('spring/themes/'), isEmpty);
        // The next start that has the network downloads.
        server.handler = (_) => _ok(_ocean);
        await start(once);
        expect(await files.list('spring/themes/'), hasLength(2));
      },
    );

    test('an error status, a timeout, a big file, bad text', () async {
      final bundled = _primary(SpringThemes(once), 'ocean');
      server.handler = (_) => HttpResponse(500);
      var (themes, _) = await start(once);
      expect(_primary(themes, 'ocean'), bundled);

      server.handler = (_) => Completer<HttpResponse>().future; // never
      (themes, _) = await start(
        once,
        timeout: const Duration(milliseconds: 50),
      );
      expect(_primary(themes, 'ocean'), bundled);

      server.handler = (_) => _ok(_ocean);
      (themes, _) = await start(once, maxBytes: 10);
      expect(_primary(themes, 'ocean'), bundled);

      server.handler = (_) => HttpResponse(200, body: const [0xff, 0xfe, 0x00]);
      (themes, _) = await start(once);
      expect(_primary(themes, 'ocean'), bundled);

      server.handler = (_) => _ok('a: [unclosed');
      (themes, _) = await start(once);
      expect(_primary(themes, 'ocean'), bundled);

      server.handler = (_) => _ok('seed-color: purpel\n');
      (themes, _) = await start(once);
      expect(_primary(themes, 'ocean'), bundled);
      expect(await files.list('spring/themes/'), isEmpty);
    });

    test('a redirect to http is refused, one to https is followed', () async {
      final bundled = _primary(SpringThemes(once), 'ocean');
      server.handler = (r) => HttpResponse(
        302,
        headers: HttpHeaders({'Location': 'http://example.com/t.yml'}),
      );
      var (themes, _) = await start(once);
      expect(_primary(themes, 'ocean'), bundled);

      server.handler = (r) => r.url.host == 'cdn.example.com'
          ? _ok(_oceanBlue)
          : HttpResponse(
              302,
              headers: HttpHeaders({
                'Location': 'https://cdn.example.com/t.yml',
              }),
            );
      (themes, _) = await start(once);
      final blue = ColorScheme.fromSeed(seedColor: const Color(0xFF0000FF));
      expect(_primary(themes, 'ocean'), blue.primary);
      expect(server.requests.last.followRedirects, isFalse);
    });
  });

  group('what the file may set', () {
    test('only theme keys; the rest is ignored (and nothing else changes)', () {
      final content = ThemeSourceContent.parse('''
spring:
  datasource:
    url: sqlite:evil.db
  flutter:
    theme:
      active: dark
      system-light: dark
      seed-color: '#0000FF'
      themes:
        ocean:
          source: https://evil.example/t.yml
          refresh: 1s
          brightness: dark
server:
  port: 1
''', 'brand');
      expect(content.properties, {
        'themes.brand.seed-color': '#0000FF',
        'themes.brand.brightness': 'dark',
      });
      expect(
        content.ignored,
        unorderedEquals([
          'spring.datasource.url',
          'spring.flutter.theme.active',
          'spring.flutter.theme.system-light',
          'spring.flutter.theme.themes.ocean.source',
          'spring.flutter.theme.themes.ocean.refresh',
          'server.port',
        ]),
      );
    });

    test('the file does not choose the active theme', () async {
      server.handler = (_) => _ok('''
spring.flutter.theme.active: dark
spring.flutter.theme.seed-color: '#0000FF'
''');
      final (themes, _) = await start(once);
      expect(themes.config.active, 'ocean');
      expect(ThemeSelection(themes).active, 'ocean');
    });
  });

  group('names and extends', () {
    test(
      'github: shorthand downloads from raw.githubusercontent.com',
      () async {
        server.handler = (_) => _ok(_ocean);
        final props = {
          'active': 'ocean',
          'themes.ocean.source': 'github:neon/themes/themes/ocean.yml@v3',
        };
        await start(props);
        expect(
          server.requests.single.url.toString(),
          'https://raw.githubusercontent.com/neon/themes/v3/themes/ocean.yml',
        );
      },
    );

    test('a theme of the app extends the downloaded one', () async {
      server.handler = (_) => _ok(_oceanBlue);
      final props = {
        ...once,
        'active': 'ocean-dark',
        'themes.ocean-dark.extends': 'ocean',
        'themes.ocean-dark.brightness': 'dark',
      };
      final (themes, _) = await start(props);
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF0000FF),
        brightness: Brightness.dark,
      );
      expect(themes.material('ocean-dark').colorScheme.primary, scheme.primary);
      expect(ThemeSelection(themes).active, 'ocean-dark');
    });

    test(
      'two downloaded themes, and a theme loaded at run time on top',
      () async {
        server.handler = (r) =>
            _ok(r.url.path.endsWith('a.yml') ? _ocean : _oceanBlue);
        final props = {
          'themes.a.source': 'https://x.example/a.yml',
          'themes.b.source': 'https://x.example/b.yml',
        };
        final (themes, _) = await start(props);
        final red = ColorScheme.fromSeed(seedColor: const Color(0xFFFF0000));
        final blue = ColorScheme.fromSeed(seedColor: const Color(0xFF0000FF));
        expect(_primary(themes, 'a'), red.primary);
        expect(_primary(themes, 'b'), blue.primary);
        themes.load({'themes.c.seed-color': 'teal'});
        expect(_primary(themes, 'a'), red.primary);
        themes.unload();
        expect(themes.names, containsAll(['a', 'b']));
        expect(themes.names, isNot(contains('c')));
      },
    );
  });
}

class _Recording implements FileStore {
  _Recording(this.inner);
  final FileStore inner;
  final writes = <String>[];

  @override
  Future<void> write(FilePlace place, String path, List<int> bytes) {
    writes.add('${place.name}:$path');
    return inner.write(place, path, bytes);
  }

  @override
  Future<Uint8List?> read(FilePlace place, String path) =>
      inner.read(place, path);
  @override
  Future<bool> exists(FilePlace place, String path) =>
      inner.exists(place, path);
  @override
  Future<bool> delete(FilePlace place, String path) =>
      inner.delete(place, path);
  @override
  Future<List<String>> list(FilePlace place, String prefix) =>
      inner.list(place, prefix);
  @override
  Future<DateTime?> modifiedAt(FilePlace place, String path) =>
      inner.modifiedAt(place, path);
  @override
  Future<TempFile> createTemp({String suffix = ''}) =>
      inner.createTemp(suffix: suffix);
  @override
  Future<TempDirectory> createTempDir() => inner.createTempDir();
  @override
  Future<void> close() => inner.close();
}

void autoConfigurationTests() {
  test(
    'the auto-configuration: a replaced FileStore carries the theme cache',
    () async {
      final server = _Server()..handler = (_) => _ok(_oceanBlue);
      final recording = _Recording(InMemoryFileStore());
      final context = await SpringApplication(
        [
          BeanModule(
            'm',
            [
              BeanDefinition<FileStore>(
                name: 'encryptedStore',
                types: const [FileStore],
                create: (_) => recording,
              ),
              BeanDefinition<HttpTransport>(
                name: 'transport',
                types: const [HttpTransport],
                create: (_) => server,
              ),
            ],
            resources: {
              'application.yml': EmbeddedResource.text('''
spring:
  flutter:
    theme:
      active: ocean
      themes:
        ocean:
          source: $_url
'''),
            },
          ),
        ],
        autoConfigurations: [springBootStarterFlutterAutoConfiguration],
        bannerMode: BannerMode.off,
      ).runAsync(const []);
      addTearDown(context.close);

      expect(context.getBean<FileStore>(), same(recording));
      final template = context.getBean<FileTemplate>();
      expect(template.fileStore, same(recording));
      expect(recording.writes, hasLength(2));
      expect(recording.writes.first, startsWith('support:spring/themes/'));
      final blue = ColorScheme.fromSeed(seedColor: const Color(0xFF0000FF));
      expect(_primary(SpringThemes.of(context), 'ocean'), blue.primary);
      expect(ThemeSelection.of(context).active, 'ocean');
    },
  );

  test(
    'without a store of the app, the platform store backs FileTemplate',
    () async {
      final context = await SpringApplication(
        [BeanModule('m', const [])],
        autoConfigurations: [springBootStarterFlutterAutoConfiguration],
        bannerMode: BannerMode.off,
      ).runAsync(const []);
      addTearDown(context.close);
      expect(
        context.getBean<FileTemplate>().fileStore,
        context.getBean<FileStore>(),
      );
    },
  );
}
