// Static resources through MockMvc (the same dispatcher a server uses):
// spring.web.resources.*, the welcome page, the single-page-app fallback,
// caching, precompressed variants, ResourceHandlerRegistry, CORS, filters
// before files and controllers before files.
import 'dart:io' as io;

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Writes [files] (relative path → content) under [root].
void writeFiles(io.Directory root, Map<String, Object> files) {
  for (final MapEntry(:key, :value) in files.entries) {
    final file = io.File('${root.path}/$key')..createSync(recursive: true);
    switch (value) {
      case final String text:
        file.writeAsStringSync(text);
      case final List<int> bytes:
        file.writeAsBytesSync(bytes);
    }
  }
}

/// The site most tests serve.
const siteFiles = <String, Object>{
  'index.html': '<h1>home</h1>',
  'app.js': 'console.log("plain");',
  'app.js.br': 'BROTLI',
  'app.js.gz': 'GZIP',
  'style.css': 'body{}',
  'data.xyz': 'custom',
  'noext': 'no extension',
  'main.dart.wasm': [0, 97, 115, 109],
  'manifest.webmanifest': '{}',
  'sub/page.html': '<p>page</p>',
  'api/books/978-0': 'a file shadowed by a controller',
  'plain/text': 'a file under a POST mapping',
  '.env': 'SECRET=1',
  '.git/config': '[core]',
  'sub/.hidden.txt': 'hidden',
  '.well-known/apple-app-site-association': '{"applinks":{}}',
  '.well-known/assetlinks.json': '[]',
  '.well-known/.secret': 'hidden in well-known',
  'docs/readme.txt': 'docs',
  'guide/index.html': '<h1>guide</h1>',
  'docs/v0.7/index.html': '<h1>docs 0.7</h1>',
  '.private/index.html': 'hidden index',
};

void main() {
  late io.Directory site;
  late io.Directory extra;

  setUpAll(() {
    site = io.Directory.systemTemp.createTempSync('static_site_');
    extra = io.Directory.systemTemp.createTempSync('static_extra_');
    writeFiles(site, siteFiles);
    writeFiles(extra, {'guide.html': '<p>guide</p>', 'index.html': 'extra'});
    // A folder that is a link out of the site: its index.html is outside.
    io.Link('${site.path}/linked').createSync(extra.path);
  });

  tearDownAll(() {
    site.deleteSync(recursive: true);
    extra.deleteSync(recursive: true);
  });

  // A context with the site as the only static location, in the mock web
  // environment; [body] gets its MockMvc.
  Future<void> withSite(
    Future<void> Function(MockMvc mvc) body, {
    List<String> properties = const [],
    ApplicationContextRunner Function(ApplicationContextRunner runner)? setUp,
  }) {
    var runner = webRunner([
      'spring.test.web-environment=mock',
      'spring.web.resources.static-locations=file:${site.path}/',
      ...properties,
    ]);
    if (setUp != null) {
      runner = setUp(runner);
    }
    return runner.runAsync((context) async {
      expect(context.startupFailure, isNull);
      await body(MockMvc.of(context.context));
    });
  }

  group('answers', () {
    test('a file with its type, nosniff, ETag, Last-Modified', () async {
      await withSite((mvc) async {
        final result = await mvc.get('/app.js');
        final headers = result.response.headers;
        expect(result.response.statusCode, 200);
        expect(result.response.bodyText, 'console.log("plain");');
        expect(headers.contentType, 'text/javascript');
        expect(headers['X-Content-Type-Options'], 'nosniff');
        expect(headers.eTag, startsWith('W/"'));
        expect(headers.lastModified, isNotNull);
        expect(headers[HttpHeaders.acceptRangesHeader], 'bytes');
        expect(headers.contentLength, 21);
        // No caching configured: no Cache-Control, as in Spring.
        expect(headers[HttpHeaders.cacheControlHeader], isNull);
      });
    });

    test('media types by extension, never sniffed', () async {
      await withSite((mvc) async {
        Future<String?> type(String path) async =>
            (await mvc.get(path)).response.headers.contentType;
        expect(await type('/style.css'), 'text/css');
        expect(await type('/main.dart.wasm'), 'application/wasm');
        expect(
          await type('/manifest.webmanifest'),
          'application/manifest+json',
        );
        expect(await type('/sub/page.html'), 'text/html');
        expect(await type('/noext'), 'application/octet-stream');
        expect(await type('/data.xyz'), 'application/octet-stream');
      });
      await withSite(
        (mvc) async {
          final result = await mvc.get('/data.xyz');
          expect(result.response.headers.contentType, 'application/x-custom');
          expect(
            (await mvc.get('/app.js')).response.headers.contentType,
            'text/x-script',
          );
        },
        properties: [
          'server.mime-mappings.xyz=application/x-custom',
          'server.mime-mappings.JS=text/x-script',
        ],
      );
    });

    test('HEAD: the headers without a body', () async {
      await withSite((mvc) async {
        final result = await mvc.perform(
          MockRequestBuilder(HttpMethod.head, '/app.js'),
        );
        expect(result.response.statusCode, 200);
        expect(result.response.bodyBytes, isEmpty);
        expect(result.response.headers.contentLength, 21);
        expect(result.response.headers.contentType, 'text/javascript');
      });
    });

    test('304 for If-None-Match and If-Modified-Since', () async {
      await withSite((mvc) async {
        final first = await mvc.get('/app.js');
        final eTag = first.response.headers.eTag!;
        final modified =
            first.response.headers[HttpHeaders.lastModifiedHeader]!;

        final byTag = await mvc.get(
          '/app.js',
          headers: {HttpHeaders.ifNoneMatchHeader: eTag},
        );
        expect(byTag.response.statusCode, 304);
        expect(byTag.response.bodyBytes, isEmpty);
        expect(byTag.response.headers.eTag, eTag);

        final byDate = await mvc.get(
          '/app.js',
          headers: {HttpHeaders.ifModifiedSinceHeader: modified},
        );
        expect(byDate.response.statusCode, 304);

        // If-None-Match wins: another tag is a full answer whatever the
        // date says.
        final other = await mvc.get(
          '/app.js',
          headers: {
            HttpHeaders.ifNoneMatchHeader: 'W/"other"',
            HttpHeaders.ifModifiedSinceHeader: modified,
          },
        );
        expect(other.response.statusCode, 200);
        expect(other.response.bodyText, 'console.log("plain");');

        final old = await mvc.get(
          '/app.js',
          headers: {
            HttpHeaders.ifUnmodifiedSinceHeader: HttpHeaders.formatDate(
              DateTime.utc(2000),
            ),
          },
        );
        expect(old.response.statusCode, 412);
      });
    });

    test('Range: one range is a 206, past the end a 416', () async {
      await withSite((mvc) async {
        final part = await mvc.get(
          '/app.js',
          headers: {HttpHeaders.rangeHeader: 'bytes=0-6'},
        );
        expect(part.response.statusCode, 206);
        expect(part.response.bodyText, 'console');
        expect(
          part.response.headers[HttpHeaders.contentRangeHeader],
          'bytes 0-6/21',
        );
        final none = await mvc.get(
          '/app.js',
          headers: {HttpHeaders.rangeHeader: 'bytes=500-'},
        );
        expect(none.response.statusCode, 416);
        // If-Range with a weak tag never matches: the whole content.
        final weak = await mvc.get(
          '/app.js',
          headers: {
            HttpHeaders.rangeHeader: 'bytes=0-6',
            HttpHeaders.ifRangeHeader: part.response.headers.eTag!,
          },
        );
        expect(weak.response.statusCode, 200);
        final byDate = await mvc.get(
          '/app.js',
          headers: {
            HttpHeaders.rangeHeader: 'bytes=0-6',
            HttpHeaders.ifRangeHeader:
                part.response.headers[HttpHeaders.lastModifiedHeader]!,
          },
        );
        expect(byDate.response.statusCode, 206);
      });
    });

    test('only GET and HEAD: OPTIONS gets Allow, others 405', () async {
      await withSite((mvc) async {
        final post = await mvc.post('/app.js', body: 'x');
        expect(post.response.statusCode, 405);
        expect(post.response.headers[HttpHeaders.allowHeader], 'GET, HEAD');
        final delete = await mvc.delete('/app.js');
        expect(delete.response.statusCode, 405);
        final options = await mvc.perform(
          MockRequestBuilder(HttpMethod.options, '/app.js'),
        );
        expect(options.response.statusCode, 200);
        expect(
          options.response.headers[HttpHeaders.allowHeader],
          'GET,HEAD,OPTIONS',
        );
        // A path without a file is a 404 for every method, as in Spring.
        expect(
          (await mvc.post('/missing.js', body: 'x')).response.statusCode,
          404,
        );
      });
    });

    test('the welcome page at /, for clients that take HTML', () async {
      await withSite((mvc) async {
        final home = await mvc.get('/', headers: {'Accept': 'text/html'});
        expect(home.response.statusCode, 200);
        expect(home.response.bodyText, '<h1>home</h1>');
        expect(home.response.headers.contentType, 'text/html');
        final any = await mvc.get('/');
        expect(any.response.statusCode, 200);
        final json = await mvc.get(
          '/',
          headers: {'Accept': 'application/json'},
        );
        expect(json.response.statusCode, 404);
      });
    });

    test('no directory listings, no index.html below /', () async {
      await withSite((mvc) async {
        for (final path in [
          '/sub/',
          '/sub',
          '/docs/',
          '/docs',
          '/.well-known/',
        ]) {
          expect(
            (await mvc.get(
              path,
              headers: {'Accept': 'text/html'},
            )).response.statusCode,
            404,
            reason: path,
          );
        }
        // A file asked for as a directory is no file.
        expect((await mvc.get('/app.js/')).response.statusCode, 404);
      });
    });

    test('dot files hidden, .well-known served (deep-link files)', () async {
      await withSite((mvc) async {
        for (final path in [
          '/.env',
          '/.git/config',
          '/sub/.hidden.txt',
          '/.well-known/.secret',
        ]) {
          expect((await mvc.get(path)).response.statusCode, 404, reason: path);
        }
        final aasa = await mvc.get('/.well-known/apple-app-site-association');
        expect(aasa.response.statusCode, 200);
        expect(aasa.response.headers.contentType, 'application/json');
        expect(aasa.response.bodyText, '{"applinks":{}}');
        final assetLinks = await mvc.get('/.well-known/assetlinks.json');
        expect(assetLinks.response.statusCode, 200);
        expect(assetLinks.response.headers.contentType, 'application/json');
      });
    });

    test('controllers win over files of the same path', () async {
      await withSite((mvc) async {
        final result = await mvc.get('/api/books/978-0');
        expect(result.response.headers.contentType, contains('json'));
        expect(result.response.bodyText, isNot(contains('shadowed')));
        // A path a controller maps for another method is the controller's
        // (a 405), as in Spring.
        final post = await mvc.get('/plain/text');
        expect(post.response.statusCode, 405);
      });
    });

    test('the context path', () async {
      await withSite(
        (mvc) async {
          expect((await mvc.get('/shop/app.js')).response.statusCode, 200);
          expect((await mvc.get('/app.js')).response.statusCode, 404);
          final home = await mvc.get(
            '/shop/',
            headers: {'Accept': 'text/html'},
          );
          expect(home.response.bodyText, '<h1>home</h1>');
        },
        properties: ['server.context-path=/shop'],
      );
    });
  });

  group('properties', () {
    test('cache.period: max-age, 0 is no-store', () async {
      await withSite(
        (mvc) async {
          final result = await mvc.get('/app.js');
          expect(
            result.response.headers[HttpHeaders.cacheControlHeader],
            'max-age=3600',
          );
          // A 304 carries it too.
          final again = await mvc.get(
            '/app.js',
            headers: {
              HttpHeaders.ifNoneMatchHeader: result.response.headers.eTag!,
            },
          );
          expect(again.response.statusCode, 304);
          expect(
            again.response.headers[HttpHeaders.cacheControlHeader],
            'max-age=3600',
          );
        },
        properties: ['spring.web.resources.cache.period=1h'],
      );
      await withSite(
        (mvc) async {
          expect(
            (await mvc.get('/app.js'))
                .response
                .headers[HttpHeaders.cacheControlHeader],
            'no-store',
          );
        },
        properties: ['spring.web.resources.cache.period=0'],
      );
    });

    test('cache.cachecontrol.* wins over the period', () async {
      await withSite(
        (mvc) async {
          expect(
            (await mvc.get('/app.js'))
                .response
                .headers[HttpHeaders.cacheControlHeader],
            'max-age=60, must-revalidate, no-transform, public, '
            'proxy-revalidate, s-maxage=30, stale-if-error=5, '
            'stale-while-revalidate=10',
          );
        },
        properties: [
          'spring.web.resources.cache.period=1h',
          'spring.web.resources.cache.cachecontrol.max-age=60',
          'spring.web.resources.cache.cachecontrol.must-revalidate=true',
          'spring.web.resources.cache.cachecontrol.no-transform=true',
          'spring.web.resources.cache.cachecontrol.cache-public=true',
          'spring.web.resources.cache.cachecontrol.proxy-revalidate=true',
          'spring.web.resources.cache.cachecontrol.s-max-age=30',
          'spring.web.resources.cache.cachecontrol.stale-if-error=5',
          'spring.web.resources.cache.cachecontrol.stale-while-revalidate=10',
        ],
      );
      await withSite(
        (mvc) async {
          expect(
            (await mvc.get('/app.js'))
                .response
                .headers[HttpHeaders.cacheControlHeader],
            'no-store, private',
          );
        },
        properties: [
          'spring.web.resources.cache.cachecontrol.max-age=60',
          'spring.web.resources.cache.cachecontrol.no-cache=true',
          'spring.web.resources.cache.cachecontrol.no-store=true',
          'spring.web.resources.cache.cachecontrol.cache-private=true',
        ],
      );
    });

    test('cache.use-last-modified=false: no Last-Modified', () async {
      await withSite(
        (mvc) async {
          final result = await mvc.get('/app.js');
          expect(
            result.response.headers[HttpHeaders.lastModifiedHeader],
            isNull,
          );
          final since = await mvc.get(
            '/app.js',
            headers: {
              HttpHeaders.ifModifiedSinceHeader: HttpHeaders.formatDate(
                DateTime.now().toUtc().add(const Duration(days: 1)),
              ),
            },
          );
          expect(since.response.statusCode, 200);
        },
        properties: ['spring.web.resources.cache.use-last-modified=false'],
      );
    });

    test('chain.compressed: precompressed variants', () async {
      await withSite(
        (mvc) async {
          Future<MvcResult> get(String? encoding) => mvc.get(
            '/app.js',
            headers: {'Accept-Encoding': ?encoding},
          );
          final br = await get('gzip, deflate, br');
          expect(br.response.bodyText, 'BROTLI');
          expect(br.response.headers[HttpHeaders.contentEncodingHeader], 'br');
          expect(br.response.headers.contentType, 'text/javascript');
          expect(
            br.response.headers[HttpHeaders.varyHeader],
            'Accept-Encoding',
          );
          final gzip = await get('gzip');
          expect(gzip.response.bodyText, 'GZIP');
          expect(
            gzip.response.headers[HttpHeaders.contentEncodingHeader],
            'gzip',
          );
          final noBr = await get('br;q=0, gzip;q=0.5');
          expect(noBr.response.bodyText, 'GZIP');
          final plain = await get(null);
          expect(plain.response.bodyText, 'console.log("plain");');
          expect(
            plain.response.headers[HttpHeaders.contentEncodingHeader],
            isNull,
          );
          expect(
            plain.response.headers[HttpHeaders.varyHeader],
            'Accept-Encoding',
          );
          // Each variant has its own tag.
          expect(br.response.headers.eTag, isNot(plain.response.headers.eTag));
          // A file without variants gets no Vary.
          final css = await mvc.get(
            '/style.css',
            headers: {'Accept-Encoding': 'br'},
          );
          expect(css.response.headers[HttpHeaders.varyHeader], isNull);
        },
        properties: ['spring.web.resources.chain.compressed=true'],
      );
      // Off by default: the variants are plain files.
      await withSite((mvc) async {
        final result = await mvc.get(
          '/app.js',
          headers: {'Accept-Encoding': 'br'},
        );
        expect(result.response.bodyText, 'console.log("plain");');
      });
    });

    test('static-path-pattern moves the files; no welcome page', () async {
      await withSite(
        (mvc) async {
          expect((await mvc.get('/static/app.js')).response.statusCode, 200);
          expect((await mvc.get('/app.js')).response.statusCode, 404);
          expect(
            (await mvc.get(
              '/',
              headers: {'Accept': 'text/html'},
            )).response.statusCode,
            404,
          );
        },
        properties: ['spring.mvc.static-path-pattern=/static/**'],
      );
    });

    test('add-mappings=false: no files', () async {
      await withSite(
        (mvc) async {
          expect((await mvc.get('/app.js')).response.statusCode, 404);
          expect(
            (await mvc.get(
              '/',
              headers: {'Accept': 'text/html'},
            )).response.statusCode,
            404,
          );
        },
        properties: ['spring.web.resources.add-mappings=false'],
      );
    });

    test('several locations: the first with the file wins', () async {
      final locations = 'file:${extra.path},file:${site.path}/';
      await withSite(
        (mvc) async {
          expect((await mvc.get('/index.html')).response.bodyText, 'extra');
          expect((await mvc.get('/app.js')).response.statusCode, 200);
          expect((await mvc.get('/guide.html')).response.statusCode, 200);
        },
        properties: [
          'spring.web.resources.static-locations=$locations',
        ],
      );
    });

    test('a missing location finds nothing and fails nothing', () async {
      await withSite(
        (mvc) async {
          expect((await mvc.get('/app.js')).response.statusCode, 404);
        },
        properties: [
          'spring.web.resources.static-locations=file:${site.path}/nowhere/',
        ],
      );
    });

    test('a location that cannot be read stops the start', () async {
      for (final location in [
        'classpath:/static/',
        'resources:',
        'https://x/',
      ]) {
        await webRunner([
          'spring.test.web-environment=mock',
          'spring.web.resources.static-locations=$location',
        ]).runAsync((context) {
          expect(context.startupFailure, isNotNull, reason: location);
        });
      }
    });
  });

  group('single-page app fallback', () {
    final properties = ['spring.web.resources.spa-fallback=true'];
    const html = {'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8'};

    test('a deep link of a browser gets index.html', () async {
      await withSite((mvc) async {
        final result = await mvc.get('/books/42', headers: html);
        expect(result.response.statusCode, 200);
        expect(result.response.bodyText, '<h1>home</h1>');
        expect(result.response.headers.contentType, 'text/html');
        final head = await mvc.perform(
          MockRequestBuilder(HttpMethod.head, '/books/42')
            ..headers.addAll(html),
        );
        expect(head.response.statusCode, 200);
      }, properties: properties);
    });

    test('not for files, scripts, other methods or .well-known', () async {
      await withSite((mvc) async {
        // A missing file (an extension), a script's fetch (*/*), a POST,
        // .well-known, hidden and refused paths: still 404.
        expect(
          (await mvc.get('/missing.js', headers: html)).response.statusCode,
          404,
        );
        expect((await mvc.get('/books/42')).response.statusCode, 404);
        expect(
          (await mvc.get(
            '/books/42',
            headers: {'Accept': '*/*'},
          )).response.statusCode,
          404,
        );
        expect(
          (await mvc.post(
            '/books/42',
            body: 'x',
            headers: html,
          )).response.statusCode,
          404,
        );
        expect(
          (await mvc.get(
            '/.well-known/assetlinks',
            headers: html,
          )).response.statusCode,
          404,
        );
        expect(
          (await mvc.get('/.env', headers: html)).response.statusCode,
          404,
        );
        // A controller's path is the controller's.
        expect(
          (await mvc.get(
            '/api/books/978-0',
            headers: html,
          )).response.headers.contentType,
          contains('json'),
        );
      }, properties: properties);
    });

    test('off by default', () async {
      await withSite((mvc) async {
        expect(
          (await mvc.get('/books/42', headers: html)).response.statusCode,
          404,
        );
      });
    });
  });

  group('directory index', () {
    final properties = ['spring.web.resources.directory-index=true'];

    test("a folder's index.html at its path, with or without /", () async {
      await withSite((mvc) async {
        for (final path in ['/guide', '/guide/']) {
          final result = await mvc.get(path);
          expect(result.response.statusCode, 200, reason: path);
          expect(result.response.bodyText, '<h1>guide</h1>', reason: path);
          expect(result.response.headers.contentType, 'text/html');
        }
        // Any client: a crawler need not send Accept: text/html.
        expect(
          (await mvc.get(
            '/docs/v0.7',
            headers: {'Accept': '*/*'},
          )).response.bodyText,
          '<h1>docs 0.7</h1>',
        );
        final head = await mvc.perform(
          MockRequestBuilder(HttpMethod.head, '/guide'),
        );
        expect(head.response.statusCode, 200);
        // A folder without index.html: no listing.
        expect((await mvc.get('/docs')).response.statusCode, 404);
        expect((await mvc.get('/docs/')).response.statusCode, 404);
      }, properties: properties);
    });

    test('before the single-page fallback, which keeps the rest', () async {
      const html = {'Accept': 'text/html'};
      await withSite((mvc) async {
        expect(
          (await mvc.get('/guide', headers: html)).response.bodyText,
          '<h1>guide</h1>',
        );
        expect(
          (await mvc.get('/books/42', headers: html)).response.bodyText,
          '<h1>home</h1>',
        );
      }, properties: [...properties, 'spring.web.resources.spa-fallback=true']);
    });

    test('no way out of the site, no hidden folder', () async {
      await withSite((mvc) async {
        for (final path in [
          '/linked',
          '/linked/',
          '/.private',
          '/.private/',
          '/guide/..',
          '/guide/%2e%2e',
          '/guide/%2e%2e/.private',
          '/%2e%2e/${extra.uri.pathSegments.where((s) => s.isNotEmpty).last}',
          '/guide%2f..%2f.private',
          '/.git',
        ]) {
          final result = await mvc.get(path);
          expect(result.response.bodyText, isNot('extra'), reason: path);
          expect(
            result.response.bodyText,
            isNot(contains('hidden index')),
            reason: path,
          );
        }
        expect((await mvc.get('/linked')).response.statusCode, 404);
        expect((await mvc.get('/.private')).response.statusCode, 404);
      }, properties: properties);
    });

    test('off by default, as in Spring Boot', () async {
      await withSite((mvc) async {
        expect((await mvc.get('/guide')).response.statusCode, 404);
      });
    });
  });

  group('ResourceHandlerRegistry', () {
    test('more mappings; the most specific pattern serves', () async {
      await withSite(
        (mvc) async {
          final guide = await mvc.get('/docs/guide.html');
          expect(guide.response.bodyText, '<p>guide</p>');
          expect(
            guide.response.headers[HttpHeaders.cacheControlHeader],
            'max-age=31536000, public, immutable',
          );
          expect(
            guide.response.headers[HttpHeaders.lastModifiedHeader],
            isNull,
          );
          // /docs/readme.txt is in the site, not in /docs/**'s location.
          expect((await mvc.get('/docs/readme.txt')).response.statusCode, 404);
          expect((await mvc.get('/app.js')).response.statusCode, 200);
          final period = await mvc.get('/p/guide.html');
          expect(
            period.response.headers[HttpHeaders.cacheControlHeader],
            'max-age=10',
          );
        },
        setUp: (runner) => runner.withBean<WebMvcConfigurer>(
          () => _Configurer((registry) {
            registry
                .addResourceHandler(['/docs/**'])
                .addResourceLocations(['file:${extra.path}'])
                .setUseLastModified(false)
                .setCacheControl(
                  CacheControl.maxAge(const Duration(days: 365))
                      .cachePublic()
                      .immutable(),
                );
            registry
                .addResourceHandler(['/p/**'])
                .addResourceLocations(['file:${extra.path}'])
                .setCachePeriod(10);
          }),
        ),
      );
    });

    test('the same pattern as the default replaces it', () async {
      await withSite(
        (mvc) async {
          expect((await mvc.get('/guide.html')).response.statusCode, 200);
          expect((await mvc.get('/app.js')).response.statusCode, 404);
          // The welcome page is the index.html /index.html gets.
          expect(
            (await mvc.get(
              '/',
              headers: {'Accept': 'text/html'},
            )).response.bodyText,
            'extra',
          );
        },
        setUp: (runner) => runner.withBean<WebMvcConfigurer>(
          () => _Configurer(
            (registry) => registry
                .addResourceHandler(['/**'])
                .addResourceLocations(['file:${extra.path}/']),
          ),
        ),
      );
    });
  });

  group('around the files', () {
    test('filters (the security chain) run before the files', () async {
      await withSite(
        (mvc) async {
          final denied = await mvc.get('/app.js');
          expect(denied.response.statusCode, 401);
          expect(denied.response.bodyText, isNot(contains('plain')));
          final allowed = await mvc.get(
            '/app.js',
            headers: {'Authorization': 'Bearer ok'},
          );
          expect(allowed.response.statusCode, 200);
          expect(allowed.response.headers['X-Trace'], 'on');
        },
        setUp: (runner) => runner.withBean<WebFilter>(_GuardFilter.new),
      );
    });

    test('CORS: the global rules apply to the files', () async {
      await withSite(
        (mvc) async {
          final allowed = await mvc.get(
            '/app.js',
            headers: {'Origin': 'https://cdn.example'},
          );
          expect(allowed.response.statusCode, 200);
          expect(
            allowed.response.headers['Access-Control-Allow-Origin'],
            'https://cdn.example',
          );
          final refused = await mvc.get(
            '/app.js',
            headers: {'Origin': 'https://evil.example'},
          );
          expect(refused.response.statusCode, 403);
          expect(refused.response.bodyText, isNot(contains('plain')));
          final preFlight = await mvc.perform(
            MockRequestBuilder(HttpMethod.options, '/app.js')
              ..headers.addAll({
                'Origin': 'https://cdn.example',
                'Access-Control-Request-Method': 'GET',
              }),
          );
          expect(preFlight.response.statusCode, 200);
          expect(
            preFlight.response.headers['Access-Control-Allow-Methods'],
            contains('GET'),
          );
        },
        setUp: (runner) => runner.withBean<WebMvcConfigurer>(
          () => _Configurer(
            (_) {},
            cors: (registry) => registry.addMapping('/**').allowedOrigins([
              'https://cdn.example',
            ]),
          ),
        ),
      );
    });
  });

  group('resources: locations', () {
    test('embedded files of lib/resources/static/', () async {
      Resources.registerAll({
        'static/embedded.txt': const EmbeddedResource.text('embedded'),
        'static/.hidden': const EmbeddedResource.text('hidden'),
        'public/pub.txt': const EmbeddedResource.text('public'),
        'application.yaml': const EmbeddedResource.text('secret: 1'),
      }, owner: 'static_resources_test');
      addTearDown(
        () => Resources.registerAll(const {}, owner: 'static_resources_test'),
      );
      await webRunner(['spring.test.web-environment=mock']).runAsync((
        context,
      ) async {
        final mvc = MockMvc.of(context.context);
        final result = await mvc.get('/embedded.txt');
        expect(result.response.statusCode, 200);
        expect(result.response.bodyText, 'embedded');
        expect(result.response.headers.contentType, 'text/plain');
        expect(result.response.headers.eTag, startsWith('W/"8-'));
        expect(result.response.headers[HttpHeaders.lastModifiedHeader], isNull);
        final again = await mvc.get(
          '/embedded.txt',
          headers: {
            HttpHeaders.ifNoneMatchHeader: result.response.headers.eTag!,
          },
        );
        expect(again.response.statusCode, 304);
        expect((await mvc.get('/pub.txt')).response.bodyText, 'public');
        expect((await mvc.get('/.hidden')).response.statusCode, 404);
        expect((await mvc.get('/application.yaml')).response.statusCode, 404);
        final range = await mvc.get(
          '/embedded.txt',
          headers: {HttpHeaders.rangeHeader: 'bytes=0-2'},
        );
        expect(range.response.statusCode, 206);
        expect(range.response.bodyText, 'emb');
      });
    });

    test('lib/resources/static/ of a test resources directory', () async {
      final resources = io.Directory.systemTemp.createTempSync('static_res_');
      addTearDown(() => resources.deleteSync(recursive: true));
      writeFiles(resources, {'static/from-dir.txt': 'from dir'});
      final remove = Resources.addDirectory(resources.path);
      addTearDown(remove);
      await webRunner(['spring.test.web-environment=mock']).runAsync((
        context,
      ) async {
        final mvc = MockMvc.of(context.context);
        final result = await mvc.get('/from-dir.txt');
        expect(result.response.bodyText, 'from dir');
        expect(result.response.headers.lastModified, isNotNull);
      });
    });
  });

  test('a large file is streamed whole', () async {
    final bytes = List<int>.generate(300000, (i) => i % 251);
    final big = io.File('${site.path}/big.bin')..writeAsBytesSync(bytes);
    addTearDown(big.deleteSync);
    await withSite((mvc) async {
      final result = await mvc.get('/big.bin');
      expect(result.response.bodyBytes, bytes);
    });
  });
}

final class _Configurer with WebMvcConfigurer {
  _Configurer(this.resources, {this.cors});

  final void Function(ResourceHandlerRegistry registry) resources;
  final void Function(CorsRegistry registry)? cors;

  @override
  void addResourceHandlers(ResourceHandlerRegistry registry) =>
      resources(registry);

  @override
  void addCorsMappings(CorsRegistry registry) => cors?.call(registry);
}

// Stands for the security filter chain: no token, no file.
final class _GuardFilter implements WebFilter {
  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) async {
    if (request.headers['Authorization'] != 'Bearer ok') {
      await response.send(401, 'Unauthorized');
      return;
    }
    await chain.doFilter(request, response);
  }
}
