// The attack catalog of the static resources: every request below must
// read nothing outside its location and nothing hidden. Fail closed: a
// refused path is a 404, as if the file did not exist.
//
// Three levels for every payload: the path checks alone
// (staticResourceSegments), the handler on a real directory with a secret
// next to it, and the dispatcher with the raw path (MockMvc's requests
// normalize their URIs, so the path is set as the server would pass it).
// The real server (dart:io) is covered in static_resources_server_test.dart.
//
// Compared with Spring's ResourceHttpRequestHandler.isInvalidPath /
// isInvalidEncodedPath and PathResourceResolver.checkResource: everything
// they refuse is refused here, and more (see the categories).
import 'dart:io' as io;

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_boot_starter_web/src/static_resource_path.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The attack catalog, by category: paths under the mapping (as the
/// request carries them, still percent-encoded) that must be refused.
const attackCatalog = <String, List<String>>{
  'dot segments': [
    '..',
    '.',
    '../secret.txt',
    '../../secret.txt',
    'sub/../../secret.txt',
    './.env',
    'sub/./../../secret.txt',
    '../site-other/secret.txt',
  ],
  'percent-encoded dots': [
    '%2e%2e/secret.txt',
    '%2E%2E/secret.txt',
    '.%2e/secret.txt',
    '%2e./secret.txt',
    'sub/%2e%2e/%2e%2e/secret.txt',
    '%2e/.env',
  ],
  'encoded slashes and backslashes': [
    '..%2fsecret.txt',
    '..%2Fsecret.txt',
    '%2e%2e%2fsecret.txt',
    'sub%2f..%2f..%2fsecret.txt',
    '..%5csecret.txt',
    '..%5Csecret.txt',
    '%2e%2e%5csecret.txt',
    '%2fetc%2fpasswd',
  ],
  'raw backslashes and mixed separators': [
    r'..\secret.txt',
    r'sub\..\..\secret.txt',
    r'..\/secret.txt',
    r'.\./secret.txt',
    '..%5c..%2fsecret.txt',
    r'\\server\share\secret.txt',
  ],
  'double and triple encoding': [
    '%252e%252e/secret.txt',
    '%252e%252e%252fsecret.txt',
    '..%255csecret.txt',
    '%25252e%25252e/secret.txt',
    '%252f',
    '%2500',
    'app.js%2500.png',
  ],
  'overlong and invalid UTF-8': [
    '%c0%ae%c0%ae/secret.txt',
    '%c0%af',
    '..%c0%afsecret.txt',
    '%e0%80%ae%e0%80%ae/secret.txt',
    '%c1%9c',
    '%f0%80%80%af',
    '%ed%a0%80',
    '%ff',
    '%fe%ff',
    '%c3',
    '%',
    '%g1',
    '%2',
    'a%',
  ],
  'null bytes': [
    '%00',
    'app.js%00',
    'secret.txt%00.png',
    '..%00/secret.txt',
    'app.js\u0000',
  ],
  'control characters and whitespace': [
    '%0a',
    'app.js%0d%0a',
    '%09app.js',
    'app.js%7f',
    'app\tjs',
    'app.js\n',
    '%20app.js',
    'app.js%20',
    '%c2%85',
    ' ',
  ],
  'unicode look-alikes of dots, slashes and colons': [
    '%ef%bc%8e%ef%bc%8e/secret.txt',
    '%e2%80%a4%e2%80%a4/secret.txt',
    '%e2%80%a5/secret.txt',
    '%e3%80%82%e3%80%82/secret.txt',
    '..%e2%88%95secret.txt',
    '..%e2%81%84secret.txt',
    '..%ef%bc%8fsecret.txt',
    '..%ef%bc%bcsecret.txt',
    '..%e2%a7%b5secret.txt',
    'c%ef%bc%9a%ef%bc%bcsecret.txt',
  ],
  'raw characters beyond ASCII': ['\u00e9.txt', '\u2025/secret.txt'],
  'Windows names and streams': [
    'app.js.',
    'app.js..',
    'app.js%2e',
    '..%20/secret.txt',
    '.. /secret.txt',
    r'app.js::$DATA',
    'app.js%3a%3a%24DATA',
    'app.js:stream',
    'c:/windows/win.ini',
    'C:%5cwindows%5cwin.ini',
    'CON',
    'con.txt',
    'NUL',
    'nul.js',
    'AUX',
    'PRN.html',
    'COM1',
    'com9.txt',
    'LPT1',
    'lpt3.css',
    r'CONIN$',
    'COM%c2%b9',
    'PROGRA~1',
    'ENV~1',
    'sub/HIDDEN~1.TXT',
    'app.j*',
    'app.?s',
    'app%2a',
    'app%3fjs',
    '%22app.js%22',
    'app%3c',
    'app%3e',
    'app%7c',
  ],
  'URL schemes': [
    'file:/etc/passwd',
    'file:%2f%2fetc%2fpasswd',
    'http:%2f%2fexample.com',
    'url:file.txt',
    'jar:file.txt',
  ],
  'hidden files and directories': [
    '.env',
    '.ENV',
    '.git/config',
    '.git%2fconfig',
    '%2eenv',
    '%2Egit/config',
    'sub/.hidden.txt',
    'sub/%2ehidden.txt',
    '.well-known/.secret',
    '.well-known/../.env',
    '.well-known/%2e%2e/.env',
    'sub/.well-known/assetlinks.json',
    '.Well-Known/assetlinks.json',
    '.WELL-KNOWN/assetlinks.json',
    '.well-known.',
    '...',
    '.../secret.txt',
  ],
  'WEB-INF and META-INF': [
    'WEB-INF/web.xml',
    'web-inf/web.xml',
    'Web-Inf/web.xml',
    'META-INF/MANIFEST.MF',
    'sub/meta-inf/x',
  ],
  'matrix parameters and empty segments': [
    'app.js;v=1',
    'app.js;',
    'sub//page.html',
    '//sub//page.html',
    'sub/./page.html',
    'sub/%2e/page.html',
  ],
  'matrix parameters hiding dot segments': [
    '..;/secret.txt',
    '..;x=1/secret.txt',
    '.;/.env',
    ';/../secret.txt',
    ';x',
    '%2e%2e;x/secret.txt',
    '..;jsessionid=1/secret.txt',
  ],
};

/// Paths that must be served (so the checks do not refuse everything).
const servedPaths = {
  'app.js': 'console.log(1);',
  'sub/page.html': '<p>page</p>',
  'caf%C3%A9.txt': 'cafe',
  'a%20b.txt': 'space',
  '.well-known/assetlinks.json': '[]',
  '.well-known/apple-app-site-association': '{}',
};

/// A request whose path is exactly [path], as the server passes a target
/// it accepted (MockServerHttpRequest would normalize it).
final class RawPathRequest extends ServerHttpRequestDecorator {
  RawPathRequest(this.path, {HttpMethod method = HttpMethod.get})
    : super(MockServerHttpRequest(method, '/'));

  @override
  final String path;
}

void main() {
  late io.Directory root;
  late io.Directory site;
  late ResourceHttpRequestHandler handler;
  const secret = 'TOP-SECRET-CONTENT';

  setUpAll(() {
    root = io.Directory.systemTemp.createTempSync('static_attack_');
    site = io.Directory('${root.path}/site')..createSync();
    final files = <String, String>{
      'site/app.js': 'console.log(1);',
      'site/sub/page.html': '<p>page</p>',
      'site/café.txt': 'cafe',
      'site/a b.txt': 'space',
      'site/.env': secret,
      'site/.git/config': secret,
      'site/sub/.hidden.txt': secret,
      'site/sub/.well-known/assetlinks.json': secret,
      'site/.well-known/assetlinks.json': '[]',
      'site/.well-known/apple-app-site-association': '{}',
      'site/.well-known/.secret': secret,
      'site/WEB-INF/web.xml': secret,
      'site/META-INF/MANIFEST.MF': secret,
      // Files whose names are what a payload decodes to once: they exist,
      // and must still not be served.
      'site/%2e%2e/secret.txt': secret,
      'site/%2e/x': secret,
      'secret.txt': secret,
      'site-other/secret.txt': secret,
    };
    for (final MapEntry(:key, :value) in files.entries) {
      io.File('${root.path}/$key')
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    handler = ResourceHttpRequestHandler(locations: ['file:${site.path}/']);
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  group('the path checks refuse', () {
    for (final MapEntry(key: category, value: payloads)
        in attackCatalog.entries) {
      test(category, () {
        for (final payload in payloads) {
          final segments = staticResourceSegments(payload);
          // A payload that passes the checks must at least be harmless:
          // no segment that climbs or is hidden.
          if (segments != null) {
            fail('Accepted ${Uri.encodeFull(payload)} as $segments');
          }
        }
      });
    }

    test('a very long path is refused or read, never a crash', () {
      final long = List.filled(10000, 'a').join('/');
      expect(staticResourceSegments(long), hasLength(10000));
      expect(staticResourceSegments('${'../' * 5000}secret.txt'), isNull);
    });
  });

  group('the handler on a real directory finds nothing for', () {
    for (final MapEntry(key: category, value: payloads)
        in attackCatalog.entries) {
      test(category, () {
        for (final payload in payloads) {
          expect(
            handler.getResource(payload),
            isNull,
            reason: Uri.encodeFull(payload),
          );
        }
      });
    }
  });

  test('the handler serves the plain paths', () async {
    for (final MapEntry(key: path, value: content) in servedPaths.entries) {
      final found = handler.getResource(path);
      expect(found, isNotNull, reason: path);
      expect(await found!.resource.readAsString(), content, reason: path);
    }
  });

  group('the dispatcher answers 404 without the secret to', () {
    for (final MapEntry(key: category, value: payloads)
        in attackCatalog.entries) {
      test(category, () async {
        await webRunner([
          'spring.test.web-environment=mock',
          'spring.web.resources.static-locations=file:${site.path}/',
          'spring.web.resources.spa-fallback=true',
        ]).runAsync((context) async {
          expect(context.startupFailure, isNull);
          final dispatcher =
              context.context.getBeanByName('dispatcherHandler') as HttpHandler;
          for (final payload in payloads) {
            for (final method in [HttpMethod.get, HttpMethod.head]) {
              final response = MockServerHttpResponse();
              await dispatcher.handle(
                RawPathRequest('/$payload', method: method)
                  ..headers.set('Accept', 'text/html'),
                response,
              );
              expect(
                response.bodyText,
                isNot(contains(secret)),
                reason: Uri.encodeFull(payload),
              );
              // 404, or the single-page-app fallback's index.html, which
              // the site does not have: always 404.
              expect(
                response.statusCode,
                404,
                reason: '${method.value} ${Uri.encodeFull(payload)}',
              );
            }
          }
        });
      });
    }
  });

  test('the dispatcher serves the plain paths', () async {
    await webRunner([
      'spring.test.web-environment=mock',
      'spring.web.resources.static-locations=file:${site.path}/',
    ]).runAsync((context) async {
      final dispatcher =
          context.context.getBeanByName('dispatcherHandler') as HttpHandler;
      for (final MapEntry(key: path, value: content) in servedPaths.entries) {
        final response = MockServerHttpResponse();
        await dispatcher.handle(RawPathRequest('/$path'), response);
        expect(response.statusCode, 200, reason: path);
        expect(response.bodyText, content, reason: path);
      }
    });
  });

  group('symbolic links', () {
    // Windows needs rights for links; the checks are the same there.
    final skip = io.Platform.isWindows ? 'links need rights on Windows' : null;

    test('that leave the location are refused', () async {
      io.Link('${site.path}/out.txt').createSync('${root.path}/secret.txt');
      io.Link('${site.path}/outdir').createSync(root.path);
      io.Link('${site.path}/sibling').createSync('${root.path}/site-other');
      io.Link('${site.path}/rel.txt').createSync('../secret.txt');
      io.Link('${site.path}/chain.txt').createSync('${site.path}/out.txt');
      addTearDown(() {
        for (final name in [
          'out.txt',
          'outdir',
          'sibling',
          'rel.txt',
          'chain.txt',
        ]) {
          io.Link('${site.path}/$name').deleteSync();
        }
      });
      for (final path in [
        'out.txt',
        'outdir/secret.txt',
        'sibling/secret.txt',
        'rel.txt',
        'chain.txt',
      ]) {
        expect(handler.getResource(path), isNull, reason: path);
      }
    }, skip: skip);

    test('to hidden files inside are refused', () {
      io.Link('${site.path}/env.txt').createSync('${site.path}/.env');
      io.Link('${site.path}/git').createSync('${site.path}/.git');
      addTearDown(() {
        io.Link('${site.path}/env.txt').deleteSync();
        io.Link('${site.path}/git').deleteSync();
      });
      expect(handler.getResource('env.txt'), isNull);
      expect(handler.getResource('git/config'), isNull);
    }, skip: skip);

    test('inside the location are followed', () async {
      io.Link('${site.path}/alias.js').createSync('${site.path}/app.js');
      io.Link('${site.path}/pages').createSync('${site.path}/sub');
      addTearDown(() {
        io.Link('${site.path}/alias.js').deleteSync();
        io.Link('${site.path}/pages').deleteSync();
      });
      final alias = handler.getResource('alias.js');
      expect(await alias!.resource.readAsString(), 'console.log(1);');
      // The media type is the name asked for.
      expect(alias.filename, 'alias.js');
      expect(handler.getResource('pages/page.html'), isNotNull);
    }, skip: skip);

    test('a location that is itself a link works', () async {
      final link = io.Link('${root.path}/site-link')..createSync(site.path);
      addTearDown(link.deleteSync);
      final linked = ResourceHttpRequestHandler(
        locations: ['file:${link.path}'],
      );
      expect(linked.getResource('app.js'), isNotNull);
      expect(linked.getResource('../secret.txt'), isNull);
    }, skip: skip);
  });

  test('special files are not read (a pipe would block)', () async {
    final fifo = '${site.path}/pipe.txt';
    final made = await io.Process.run('mkfifo', [fifo]);
    if (made.exitCode != 0) {
      markTestSkipped('no mkfifo here');
      return;
    }
    addTearDown(() => io.File(fifo).deleteSync());
    expect(handler.getResource('pipe.txt'), isNull);
  }, skip: io.Platform.isWindows ? 'no pipes in the file system' : null);

  test('directories are not files', () {
    for (final path in [
      'sub',
      'sub/',
      '',
      '/',
      '.well-known',
      '.well-known/',
    ]) {
      expect(handler.getResource(path), isNull, reason: path);
    }
  });

  test('case variants find no hidden file on any file system', () {
    // On a case-insensitive file system (macOS, Windows) .ENV is .env:
    // the check is on the name asked for, so both are refused.
    for (final path in ['.ENV', '.Env', '.GIT/config', 'web-inf/web.xml']) {
      expect(handler.getResource(path), isNull, reason: path);
    }
  });
}
