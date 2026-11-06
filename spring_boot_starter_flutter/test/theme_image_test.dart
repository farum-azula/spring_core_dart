// ThemeImage: parsing, the cache, refresh with conditional requests, the
// pin, http refused, the fallback, offline. A fake HTTP transport plays the
// server; "a restart" is new themes and a new loader over the same files.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_boot_starter_flutter/spring_boot_starter_flutter.dart';
import 'package:spring_boot_starter_flutter/src/files/sha256.dart';
import 'package:spring_boot_starter_flutter/src/theme/theme_image.dart';

const _url = 'https://cdn.example.com/neon/background.jpg';

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

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

HttpResponse _ok(String body, {String? etag}) => HttpResponse(
  200,
  body: _bytes(body),
  headers: HttpHeaders({'ETag': ?etag}),
);

Map<String, String> _props([Map<String, String> image = const {}]) => {
  'background.image.source': _url,
  for (final MapEntry(:key, :value) in image.entries)
    'background.image.$key': value,
};

Uint8List _shown(ThemeImage image) => (image.provider! as MemoryImage).bytes;

void main() {
  late InMemoryFileStore store;
  late FileTemplate files;
  late _Server server;
  var now = DateTime.utc(2026, 11, 2, 12);

  setUp(() {
    now = DateTime.utc(2026, 11, 2, 12);
    store = InMemoryFileStore(clock: () => now);
    files = FileTemplate(store);
    server = _Server();
  });

  Future<(SpringThemes, ThemeImageLoader, ThemeImage)> start(
    Map<String, String> properties, {
    _Server? over,
  }) async {
    final themes = SpringThemes(properties);
    final loader = ThemeImageLoader(
      themes: themes,
      files: files,
      transport: over ?? server,
      clock: () => now,
    );
    await loader.run(ApplicationArguments(const []));
    return (themes, loader, themes.data('light').background!.image!.image!);
  }

  group('the properties', () {
    ThemeImage parse(Map<String, String> image) =>
        SpringThemes(_props(image)).data('light').background!.image!.image!;

    test('an asset path is its own provider at once', () {
      final themes = SpringThemes({
        'background.image.source': 'packages/neon_ui/assets/bg.jpg',
      });
      final image = themes.data('light').background!.image!.image!;
      expect(image.isNetwork, isFalse);
      expect((image.provider! as AssetImage).assetName, contains('bg.jpg'));
    });

    test('a header name keeps its spelling, dashes and case', () {
      final image = parse({
        'headers.X-Api-Key': 'secret',
        'headers.Authorization': 'Bearer abc',
      });
      expect(image.headers, {
        'X-Api-Key': 'secret',
        'Authorization': 'Bearer abc',
      });
    });

    test('the keys of a network image', () {
      final image = parse({
        'refresh': '1d',
        'source-sha256': 'A' * 64,
        'headers.authorization': 'Bearer abc',
        'headers.X-Api-Key': 'secret',
        'timeout': '3s',
        'fallback': 'assets/bg.jpg',
      });
      expect(image.isNetwork, isTrue);
      expect(image.refresh, const Duration(days: 1));
      expect(image.sha256, 'a' * 64);
      expect(image.headers['authorization'], 'Bearer abc');
      expect(image.headers['X-Api-Key'], 'secret');
      expect(image.timeout, const Duration(seconds: 3));
      expect((image.provider! as AssetImage).assetName, 'assets/bg.jpg');
    });

    test('http is refused with a hint unless allow-http is true', () {
      expect(
        () => SpringThemes({'background.image.source': 'http://x.test/a.png'}),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.toString(),
            'text',
            allOf(contains('allow-http'), contains('background.image.source')),
          ),
        ),
      );
      final image = SpringThemes({
        'background.image.source': 'http://x.test/a.png',
        'background.image.allow-http': 'true',
      }).data('light').background!.image!.image!;
      expect(image.uri!.scheme, 'http');
    });

    test('wrong values and keys fail the start', () {
      for (final bad in [
        {'source-sha256': 'abc'},
        {'refresh': 'soon'},
        {'timeuot': '3s'},
        {'source': 'ftp://x/a.png'},
      ]) {
        expect(() => parse(bad), throwsA(isA<ThemePropertyException>()));
      }
      expect(
        () => parse({'timeuot': '3s'}),
        throwsA(
          isA<ThemePropertyException>().having(
            (e) => e.expected,
            'expected',
            contains("did you mean 'timeout'"),
          ),
        ),
      );
    });

    test('an image token is a map with source', () {
      final themes = SpringThemes({
        'tokens.brand.logo.source': _url,
        'tokens.brand.logo.fallback': 'assets/logo.png',
        'tokens.brand.name': 'Neon',
      });
      final reader = ThemeKeyReader(themes.data('light'));
      expect(reader.tokenImage('brand.logo').source, _url);
      expect(reader.token('brand.name'), 'Neon');
      expect(() => reader.tokenImage('brand.name'), throwsStateError);
    });
  });

  group('the cache', () {
    test(
      'the start does not wait; download once, then only the cache',
      () async {
        final gate = Completer<void>();
        server.handler = (r) async {
          await gate.future;
          return _ok('one', etag: '"1"');
        };
        var (themes, loader, image) = await start(_props());
        // The start came back with the server still silent.
        expect(image.provider, isNull);
        gate.complete();
        await loader.idle;
        expect(_shown(image), _bytes('one'));
        expect(server.requests, hasLength(1));
        loader.dispose();
        themes.dispose();

        now = now.add(const Duration(days: 30));
        server.requests.clear();
        (themes, loader, image) = await start(_props());
        expect(_shown(image), _bytes('one'));
        await loader.idle;
        expect(server.requests, isEmpty);
        loader.dispose();
      },
    );

    test('headers go with the request', () async {
      server.handler = (r) => _ok('x');
      final (_, loader, _) = await start(
        _props({'headers.authorization': 'Bearer abc'}),
      );
      await loader.idle;
      expect(
        server.requests.single.headers['authorization'],
        'Bearer abc',
      );
      loader.dispose();
    });

    test(
      'offline: the fallback, no crash; the next start tries again',
      () async {
        server.handler = (r) => throw StateError('offline');
        var (_, loader, image) = await start(
          _props({'fallback': 'assets/bg.jpg'}),
        );
        await loader.idle;
        expect((image.provider! as AssetImage).assetName, 'assets/bg.jpg');
        loader.dispose();

        server.handler = (r) => _ok('late');
        (_, loader, image) = await start(_props({'fallback': 'assets/bg.jpg'}));
        await loader.idle;
        expect(_shown(image), _bytes('late'));
        loader.dispose();
      },
    );

    test('without a cache or a fallback the provider is null', () async {
      server.handler = (r) => HttpResponse(500, request: r);
      final (_, loader, image) = await start(_props());
      await loader.idle;
      expect(image.provider, isNull);
      loader.dispose();
    });

    test('http redirects are refused without allow-http', () async {
      server.handler = (r) => HttpResponse(
        302,
        headers: HttpHeaders({'Location': 'http://evil.test/a.png'}),
        request: r,
      );
      final (_, loader, image) = await start(_props());
      await loader.idle;
      expect(image.provider, isNull);
      expect(server.requests, hasLength(1));
      loader.dispose();
    });

    test('the credentials do not follow a redirect to another host', () async {
      server.handler = (r) => r.url.host == 'cdn.example.com'
          ? HttpResponse(
              302,
              headers: HttpHeaders({'Location': 'https://other.test/a.png'}),
              request: r,
            )
          : _ok('moved');
      final (_, loader, image) = await start(
        _props({'headers.authorization': 'Bearer abc'}),
      );
      await loader.idle;
      expect(_shown(image), _bytes('moved'));
      expect(server.requests.last.headers['authorization'], isNull);
      loader.dispose();
    });
  });

  group('redirects and timers', () {
    test('headers follow a redirect only to the same origin', () async {
      server.handler = (r) {
        if (r.url.path == '/neon/background.jpg') {
          return HttpResponse(
            302,
            headers: HttpHeaders({'Location': '/moved.jpg'}),
            request: r,
          );
        }
        return _ok('moved');
      };
      final (_, loader, _) = await start(
        _props({'headers.authorization': 'Bearer abc'}),
      );
      await loader.idle;
      expect(server.requests.last.url.path, '/moved.jpg');
      expect(server.requests.last.headers['authorization'], 'Bearer abc');
      loader.dispose();
    });

    test('headers do not follow https to http on the same host', () async {
      server.handler = (r) => r.url.scheme == 'https'
          ? HttpResponse(
              302,
              headers: HttpHeaders({
                'Location': 'http://cdn.example.com/a.png',
              }),
              request: r,
            )
          : _ok('plain');
      final (_, loader, image) = await start(
        _props({
          'headers.authorization': 'Bearer abc',
          'allow-http': 'true',
        }),
      );
      await loader.idle;
      expect(_shown(image), _bytes('plain'));
      expect(server.requests.last.url.scheme, 'http');
      expect(server.requests.last.headers['authorization'], isNull);
      loader.dispose();
    });

    test('headers do not follow a redirect to another port', () async {
      server.handler = (r) => r.url.port == 443
          ? HttpResponse(
              302,
              headers: HttpHeaders({
                'Location': 'https://cdn.example.com:8443/a.png',
              }),
              request: r,
            )
          : _ok('port');
      final (_, loader, _) = await start(
        _props({'headers.authorization': 'Bearer abc'}),
      );
      await loader.idle;
      expect(server.requests.last.url.port, 8443);
      expect(server.requests.last.headers['authorization'], isNull);
      loader.dispose();
    });

    test(
      'a download that ends after its image went away sets no timer',
      () async {
        final timers = <Timer>[];
        await runZoned(
          () async {
            final gate = Completer<void>();
            server.handler = (r) async {
              await gate.future;
              return _ok('late');
            };
            final themes = SpringThemes({});
            final loader = ThemeImageLoader(
              themes: themes,
              files: files,
              transport: server,
              clock: () => now,
            );
            await loader.run(ApplicationArguments(const []));
            themes.load({
              'themes.extra.background.image.source': _url,
              'themes.extra.background.image.refresh': '1h',
            });
            await Future<void>.delayed(const Duration(milliseconds: 20));
            // The theme goes away while the download runs.
            themes.unload();
            gate.complete();
            await loader.idle;
            expect(timers.where((t) => t.isActive), isEmpty);
            loader.dispose();
            themes.dispose();
          },
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              final timer = parent.createTimer(zone, duration, callback);
              if (duration >= const Duration(minutes: 1)) {
                timers.add(timer);
              }
              return timer;
            },
          ),
        );
      },
    );
  });

  group('refresh', () {
    test(
      'an old cache is read again with a conditional request and swapped',
      () async {
        server.handler = (r) => _ok('v1', etag: '"1"');
        var (_, loader, image) = await start(_props({'refresh': '1h'}));
        await loader.idle;
        expect(_shown(image), _bytes('v1'));
        loader.dispose();

        // A restart two hours later: the cache shows, the background asks.
        now = now.add(const Duration(hours: 2));
        server.requests.clear();
        server.handler = (r) => _ok('v2', etag: '"2"');
        (_, loader, image) = await start(_props({'refresh': '1h'}));
        expect(_shown(image), _bytes('v1'));
        final swaps = <ImageProvider?>[];
        image.listenable.addListener(() => swaps.add(image.provider));
        await loader.idle;
        expect(server.requests.single.headers['If-None-Match'], '"1"');
        expect(swaps, hasLength(1));
        expect(_shown(image), _bytes('v2'));
        loader.dispose();
      },
    );

    test('a 304 keeps the image and renews the cache', () async {
      server.handler = (r) => _ok('v1', etag: '"1"');
      var (_, loader, image) = await start(_props({'refresh': '1h'}));
      await loader.idle;
      loader.dispose();

      now = now.add(const Duration(hours: 2));
      server.handler = (r) => HttpResponse(304, request: r);
      (_, loader, image) = await start(_props({'refresh': '1h'}));
      final before = image.provider;
      await loader.idle;
      expect(image.provider, same(before));
      final meta = jsonDecode(
        (await files.read<String>(
          '${image.cacheFolder}/meta.json',
        ))!,
      ) as Map<String, Object?>;
      expect(meta['fetchedAt'], now.toIso8601String());
      loader.dispose();
    });

    test('a fresh cache is not asked; the timer asks when it is old', () async {
      server.handler = (r) => _ok('v1');
      var (_, loader, _) = await start(_props({'refresh': '1h'}));
      await loader.idle;
      loader.dispose();

      now = now.add(const Duration(minutes: 10));
      server.requests.clear();
      (_, loader, _) = await start(_props({'refresh': '1h'}));
      await loader.idle;
      expect(server.requests, isEmpty);
      loader.dispose();
    });
  });

  group('source-sha256', () {
    final good = _bytes('good');
    final pin = sha256Hex(good);

    test('the matching file is kept', () async {
      server.handler = (r) => _ok('good');
      final (_, loader, image) = await start(_props({'source-sha256': pin}));
      await loader.idle;
      expect(_shown(image), good);
      loader.dispose();
    });

    test('another file is refused and not cached', () async {
      server.handler = (r) => _ok('evil');
      final (_, loader, image) = await start(
        _props({'source-sha256': pin, 'fallback': 'assets/bg.jpg'}),
      );
      await loader.idle;
      expect(image.provider, isA<AssetImage>());
      expect(await files.list('spring/images/'), isEmpty);
      loader.dispose();
    });

    test('a cached file that is not the pinned one is dropped', () async {
      final image = ThemeImage(source: _url, sha256: pin);
      final bad = _bytes('bad');
      await files.write('${image.cacheFolder}/image', bad);
      await files.write(
        '${image.cacheFolder}/meta.json',
        jsonEncode({
          'source': _url,
          'sha256': sha256Hex(bad),
          'fetchedAt': now.toIso8601String(),
        }),
      );
      server.handler = (r) => HttpResponse(500, request: r);
      final (_, loader, shown) = await start(_props({'source-sha256': pin}));
      await loader.idle;
      expect(shown.provider, isNull);
      expect(await files.exists('${image.cacheFolder}/image'), isFalse);
      loader.dispose();
    });

    test('a changed pin or source downloads again; old folders go', () async {
      server.handler = (r) => _ok('good');
      var (_, loader, _) = await start(_props());
      await loader.idle;
      loader.dispose();
      final first = await files.list('spring/images/');
      expect(first, isNotEmpty);

      (_, loader, _) = await start(_props({'source-sha256': pin}));
      await loader.idle;
      final second = await files.list('spring/images/');
      expect(second, isNotEmpty);
      expect(second.toSet().intersection(first.toSet()), isEmpty);
      loader.dispose();
    });
  });

  test('the loader closes only the transport it made', () async {
    final (_, loader, _) = await start(_props());
    loader.dispose();
    expect(server.closed, isFalse);
  });
}
