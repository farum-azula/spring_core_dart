// The site and its API on one port: the files of the build, index.html
// for the app's own addresses, and the controller first.
@TestOn('vm')
library;

import 'package:test/test.dart';

import 'support/app.dart';

const html = {'Accept': 'text/html,application/xhtml+xml'};

void main() {
  final app = staticSite();

  test('/ is index.html, the welcome page', () async {
    await app.mockMvc
        .get('/', headers: html)
        .andExpect(
          status: 200,
          contentType: 'text/html',
          body: contains('flutter_bootstrap.js'),
        );
  });

  test("an address of the app's router gets index.html", () async {
    for (final path in ['/guide', '/server', '/no/such/page']) {
      await app.mockMvc
          .get(path, headers: html)
          .andExpect(
            status: 200,
            contentType: 'text/html',
            body: contains('flutter_bootstrap.js'),
          );
    }
  });

  test("a folder's index.html at its address (the SEO pages)", () async {
    for (final path in ['/about', '/about/']) {
      await app.mockMvc
          .get(path, headers: html)
          .andExpect(
            status: 200,
            contentType: 'text/html',
            body: contains('<title>About · Static site</title>'),
          );
    }
    // Any client, a crawler too.
    await app.mockMvc
        .get('/about', headers: {'Accept': '*/*'})
        .andExpect(status: 200, body: contains('About · Static site'));
  });

  test('the API is the controller, on the same origin', () async {
    final result = await app.mockMvc
        .get('/api/info', headers: {'Accept': 'application/json'})
        .andExpect(status: 200, json: containsPair('name', 'static-site'))
        .andReturn();
    final time = (result.response.json! as Map)['time']! as String;
    expect(DateTime.parse(time).isUtc, isTrue);
  });

  test('the files of the build, with their types', () async {
    await app.mockMvc
        .get('/flutter_bootstrap.js')
        .andExpect(status: 200, contentType: 'text/javascript');
    await app.mockMvc
        .get('/canvaskit/canvaskit.wasm')
        .andExpect(status: 200, contentType: 'application/wasm');
    await app.mockMvc
        .get('/assets/AssetManifest.bin.json')
        .andExpect(status: 200, contentType: 'application/json');
  });

  test('a reload asks again and gets 304 while the file is the same', () async {
    final first = await app.mockMvc
        .get('/main.dart.js')
        .andExpect(status: 200, headers: {'Cache-Control': 'no-cache'})
        .andReturn();
    final etag = first.response.headers['ETag']!;
    await app.mockMvc
        .get('/main.dart.js', headers: {'If-None-Match': etag})
        .andExpect(status: 304);
  });

  test(
    'the precompressed main.dart.js.br for a browser that takes br',
    () async {
      await app.mockMvc
          .get('/main.dart.js', headers: {'Accept-Encoding': 'gzip, br'})
          .andExpect(
            status: 200,
            contentType: 'text/javascript',
            headers: {'Content-Encoding': 'br'},
            body: 'br',
          );
    },
  );

  test('no index.html where a file or the API is expected', () async {
    // A script's fetch() of a missing path, a missing script, an unknown
    // API path: 404, not the app's page.
    await app.mockMvc
        .get('/guide', headers: {'Accept': 'application/json'})
        .andExpect(status: 404);
    await app.mockMvc.get('/missing.js', headers: html).andExpect(status: 404);
    await app.mockMvc
        .get('/api/nothing', headers: {'Accept': 'application/json'})
        .andExpect(status: 404);
  });

  test('nothing outside the build folder', () async {
    for (final path in [
      '/../pubspec.yaml',
      '/%2e%2e/pubspec.yaml',
      '/..%2fpubspec.yaml',
    ]) {
      final result = await app.mockMvc.get(path).andReturn();
      expect(result.response.statusCode, anyOf(400, 404), reason: path);
      expect(result.response.bodyText, isNot(contains('static_site_server')));
    }
  });
}
