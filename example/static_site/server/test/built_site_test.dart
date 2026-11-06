// The real build of ../app (`flutter build web`), served as the site is:
// its index.html, its main.dart.js and CanvasKit, the app's addresses.
@TestOn('vm')
@Tags(['built-site'])
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/app.dart';

const html = {'Accept': 'text/html,application/xhtml+xml'};

void main() {
  final build = Directory(inPackage('../app/build/web'));
  final required = Platform.environment['STATIC_SITE_BUILD_REQUIRED'] == 'true';
  if (!File('${build.path}/index.html').existsSync()) {
    test(
      'the built site',
      () => fail('No ../app/build/web: run `flutter build web` in ../app.'),
      skip: required ? false : 'No build of ../app (flutter build web).',
    );
    return;
  }
  final app = staticSite(web: 'file:${build.path}/');

  test("index.html, at / and at the app's addresses", () async {
    for (final path in ['/', '/guide', '/server']) {
      await app.mockMvc
          .get(path, headers: html)
          .andExpect(
            status: 200,
            contentType: 'text/html',
            body: contains('flutter_bootstrap.js'),
          );
    }
  });

  test("Flutter's files, with their types", () async {
    await app.mockMvc
        .get('/flutter_bootstrap.js')
        .andExpect(status: 200, contentType: 'text/javascript');
    await app.mockMvc
        .get('/main.dart.js')
        .andExpect(status: 200, contentType: 'text/javascript');
    await app.mockMvc
        .get('/manifest.json')
        .andExpect(status: 200, contentType: 'application/json');
    final wasm = build
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((file) => file.path.endsWith('.wasm'));
    await app.mockMvc
        .get(wasm.path.substring(build.path.length))
        .andExpect(status: 200, contentType: 'application/wasm');
  });

  test('the API next to it', () async {
    await app.mockMvc
        .get('/api/info', headers: {'Accept': 'application/json'})
        .andExpect(status: 200);
  });
}
