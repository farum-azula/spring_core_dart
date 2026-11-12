// spring.flutter.web.page.wasm-allow-list: the page passes the engines to
// Flutter's loader as config.wasmAllowList, under the app's own, with and
// without a splash; not set, the page is the one the build wrote before.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/web_page_head.dart';
import 'package:spring_core_dart_generator/src/web_page_loader.dart';
import 'package:spring_core_dart_generator/src/web_page_loader_builder.dart';
import 'package:test/test.dart';

const _page = '''
<!DOCTYPE html>
<html>
<head>
  <title>App</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

const _splash = '''
spring.flutter.theme:
  splash: { title: Hello }
''';

const _noSplash = 'spring.flutter.theme: { seed-color: red }\n';

final class _Files implements WebPageFiles {
  _Files(this.files);

  final Map<String, String> files;

  @override
  Future<String?> read(
    BuildStep buildStep,
    String package,
    String path,
  ) async => files[path];

  @override
  Future<void> write(
    BuildStep buildStep,
    String package,
    String path,
    String content,
  ) async => files[path] = content;
}

Future<({String page, List<String> logs})> _build(
  String yaml, {
  String? web,
}) async {
  final files = _Files({'web/index.html': _page});
  final logs = <String>[];
  await testBuilder(
    WebPageLoaderBuilder(files: files),
    {
      'app|pubspec.yaml':
          'name: app\ndependencies:\n  spring_boot_starter_flutter: any\n',
      'app|lib/app.dart': 'void main() {}',
      'app|lib/resources/application.yaml': yaml,
      'app|lib/resources/application-web.properties': ?web,
    },
    rootPackage: 'app',
    onLog: (record) => logs.add('${record.level.name}: ${record.message}'),
  );
  return (page: files.files['web/index.html']!, logs: logs);
}

// The text of each inline <script> of [html].
List<String> _scripts(String html) => [
  for (final match in RegExp(
    r'<script>([\s\S]*?)</script>',
  ).allMatches(html))
    match[1]!,
];

final Object _node = Process.runSync('which', ['node']).exitCode == 0
    ? false
    : 'node is not installed';

// Runs [script] in node with a fake `window._flutter.loader` whose load
// records the options it gets; [bootstrap] is the app's
// flutter_bootstrap.js. [before]: the loader is there before the script.
Future<Map<String, Object?>> _run(
  String script,
  String bootstrap, {
  bool before = false,
}) async {
  const page = '''
var attributes = {};
var root = {
  getAttribute: function (n) { return attributes[n] || null; },
  setAttribute: function (n, v) { attributes[n] = v; },
  style: { setProperty: function () {} },
  parentNode: { removeChild: function () {} }
};
globalThis.window = globalThis;
globalThis.document = { getElementById: function (id) { return id === 'spring-loader' ? root : null; } };
globalThis.requestAnimationFrame = function () {};
globalThis.CustomEvent = function (type, init) { this.type = type; this.detail = init.detail; };
globalThis.addEventListener = function () {};
globalThis.dispatchEvent = function () {};
var seen = {};
var fake = {
  load: function (options) {
    seen.config = options.config;
    return options.onEntrypointLoaded
      ? options.onEntrypointLoaded({
          initializeEngine: function (config) {
            seen.engine = config;
            return Promise.resolve({ runApp: function () {} });
          }
        })
      : Promise.resolve();
  }
};
''';
  const install =
      'window._flutter = window._flutter || {};\n'
      'window._flutter.loader = fake;\n';
  final code = before
      ? '$page$install$script\n$bootstrap'
      : '$page$script\n$install$bootstrap';
  const report =
      'setTimeout(function () { '
      'console.log(JSON.stringify(seen)); process.exit(0); }, 0);';
  final result = await Process.run('node', ['-e', '$code\n$report']);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String) as Map<String, Object?>;
}

void main() {
  group('not set', () {
    test('the script is the one it was, to the byte', () {
      // The hash a Content-Security-Policy of an existing app allows.
      expect(
        WebPageLoader.scriptHash,
        "'sha256-MsT7XidyuUte+QLs64HPO/KBzV4DO4qYux8Qq0oDoc0='",
      );
      expect(WebPageLoader.scriptFor(), WebPageLoader.script);
      expect(WebPageLoader.scriptFor(wasmAllowList: {}), WebPageLoader.script);
    });

    test('a splash: its block only, nothing of Wasm', () async {
      final (:page, :logs) = await _build(_splash);
      expect(_scripts(page), [WebPageLoader.script]);
      expect(page, isNot(contains('wasm')));
      expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
    });

    test('no splash: no block', () async {
      final (:page, logs: _) = await _build(_noSplash);
      expect(page, isNot(contains(WebPageLoader.startMarker)));
      expect(page, isNot(contains('<script>')));
    });
  });

  group('set', () {
    const yaml =
        'spring.flutter.web.page.wasm-allow-list: '
        '{ gecko: true, webkit: true }\n';

    test("with a splash: the splash's script passes it", () async {
      final (:page, :logs) = await _build('$_splash$yaml');
      final script = WebPageLoader.scriptFor(
        wasmAllowList: {'gecko': true, 'webkit': true},
      );
      expect(script, isNot(WebPageLoader.script));
      expect(_scripts(page), [script]);
      expect(page, contains('id="spring-loader"'));
      expect(script, contains('var allow = {"gecko":true,"webkit":true}'));
      // One wrapper, one defineProperty.
      expect('defineProperty'.allMatches(page), hasLength(1));
      expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
    });

    test('without a splash: a block with only the script', () async {
      final (:page, :logs) = await _build('$_noSplash$yaml');
      final block = WebPageLoader.wasmBlock({'gecko': true, 'webkit': true});
      expect(page, contains(block));
      expect(page, isNot(contains('spring-loader-style')));
      expect(page, isNot(contains('id="spring-loader"')));
      expect('defineProperty'.allMatches(page), hasLength(1));
      expect(logs.where((l) => l.startsWith('SEVERE')), isEmpty);
      // Not set again: the block is gone, the page as it was.
      final files = _Files({'web/index.html': page});
      await testBuilder(
        WebPageLoaderBuilder(files: files),
        {
          'app|pubspec.yaml':
              'name: app\ndependencies:\n  spring_boot_starter_flutter: any\n',
          'app|lib/app.dart': 'void main() {}',
          'app|lib/resources/application.yaml': _noSplash,
        },
        rootPackage: 'app',
      );
      expect(
        files.files['web/index.html'],
        isNot(contains(WebPageLoader.startMarker)),
      );
    });

    test("the web profile's file wins per engine; properties too", () async {
      final (:page, logs: _) = await _build(
        '$_noSplash$yaml',
        web:
            'spring.flutter.web.page.wasm-allow-list.webkit=false\n'
            'spring.flutter.web.page.wasm-allow-list[blink]=true\n',
      );
      expect(
        page,
        contains('var allow = {"blink":true,"gecko":true,"webkit":false}'),
      );
    });

    test('the policy of spa mode has the hash of the script', () {
      final script = WebPageLoader.wasmScript({'gecko': true});
      expect(WebPageHead.hashOf(script), startsWith("'sha256-"));
      expect(
        WebPageLoader.wasmBlock({'gecko': true}),
        contains('<script>$script</script>'),
      );
    });
  });

  group('a bad value fails the build', () {
    for (final (name, yaml, message) in [
      (
        'an unknown engine',
        'spring.flutter.web.page.wasm-allow-list: { chrome: true }\n',
        'names no browser engine',
      ),
      (
        'not true or false',
        'spring.flutter.web.page.wasm-allow-list: { gecko: yes please }\n',
        'wasm-allow-list.gecko is true or false',
      ),
      (
        'no map',
        'spring.flutter.web.page.wasm-allow-list: gecko\n',
        'is a map of browser engine',
      ),
    ]) {
      test(name, () async {
        final (:page, :logs) = await _build('$_splash$yaml');
        expect(
          logs.where((l) => l.startsWith('SEVERE')).join('\n'),
          allOf(
            contains('spring.flutter.web.page.wasm-allow-list'),
            contains(message),
          ),
        );
        expect(_scripts(page), [WebPageLoader.script]);
      });
    }
  });

  group("the script and Flutter's loader", () {
    const allow = {'gecko': true, 'webkit': true};

    test(
      'without a splash: merged under the config of flutter_bootstrap.js',
      () async {
        for (final before in [false, true]) {
          final seen = await _run(
            WebPageLoader.wasmScript(allow),
            '_flutter.loader.load({ config: { renderer: "skwasm", '
            'wasmAllowList: { webkit: false } } });',
            before: before,
          );
          expect(seen['config'], {
            'renderer': 'skwasm',
            'wasmAllowList': {'gecko': true, 'webkit': false},
          }, reason: 'loader set before the script: $before');
        }
      },
      skip: _node,
    );

    test(
      'without a config of its own: the allow list',
      () async {
        final seen = await _run(
          WebPageLoader.wasmScript(allow),
          '_flutter.loader.load();',
        );
        expect(seen['config'], {'wasmAllowList': allow});
      },
      skip: _node,
    );

    test(
      'with a splash: merged, and the engine gets the config',
      () async {
        for (final before in [false, true]) {
          final seen = await _run(
            WebPageLoader.scriptFor(wasmAllowList: allow),
            '_flutter.loader.load({ config: { wasmAllowList: '
            '{ blink: false } } });',
            before: before,
          );
          final config = {
            'wasmAllowList': {'blink': false, 'gecko': true, 'webkit': true},
          };
          expect(seen['config'], config);
          expect(seen['engine'], config);
        }
      },
      skip: _node,
    );

    test(
      "not set: Flutter's loader gets the config as it was",
      () async {
        final seen = await _run(
          WebPageLoader.script,
          '_flutter.loader.load({ config: { renderer: "canvaskit" } });',
        );
        expect(seen['config'], {'renderer': 'canvaskit'});
      },
      skip: _node,
    );
  });
}
