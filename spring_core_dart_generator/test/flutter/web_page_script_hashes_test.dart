// The scripts the build writes into web/index.html run under the policy of
// spa mode: the policy allows each by the hash of exactly the text between
// its tags, so the page and the policy must agree to the byte.
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/web_dev_config_builder.dart';
import 'package:spring_core_dart_generator/src/web_page_head.dart';
import 'package:spring_core_dart_generator/src/web_page_loader.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

final class _Files implements WebDevConfigFiles {
  String? content;

  @override
  Future<String?> read(BuildStep buildStep, String package) async => content;

  @override
  Future<void> write(BuildStep buildStep, String package, String text) async =>
      content = text;

  @override
  Future<void> delete(BuildStep buildStep, String package) async =>
      content = null;
}

// The text of each inline <script> of [html].
List<String> _scripts(String html) => [
  for (final match in RegExp(
    r'<script>([\s\S]*?)</script>',
  ).allMatches(html))
    match[1]!,
];

// The script-src of the spa policy the builder writes for [properties]
// (application-web.properties) in a Flutter app.
Future<List<String>> _scriptSrc(String properties) async {
  final files = _Files();
  await testBuilder(
    WebDevConfigBuilder(files: files),
    {
      'app|pubspec.yaml':
          'name: app\ndependencies:\n  spring_boot_starter_flutter: any\n',
      'app|lib/app.dart': 'void main() {}',
      'app|lib/resources/application-web.properties':
          'spring.flutter.security.web.mode=spa\n$properties',
    },
    rootPackage: 'app',
  );
  final server = (loadYaml(files.content!) as YamlMap)['server'] as YamlMap;
  final policy = [
    for (final header in server['headers'] as YamlList)
      if ((header as YamlMap)['name'] == 'Content-Security-Policy')
        header['value'] as String,
  ].single;
  return policy
      .split('; ')
      .singleWhere((directive) => directive.startsWith('script-src '))
      .split(' ')
      .skip(1)
      .toList();
}

void main() {
  test(
    'the swipe and pixel ratio scripts are the texts their hashes are of',
    () {
      final page = WebPageHead.pixelRatio(
        WebPageHead.swipe(
          '<html><head></head><body></body></html>',
          swipeToClose: false,
        ),
        max: 2,
      );
      expect(_scripts(page), [
        WebPageHead.swipeScript,
        WebPageHead.pixelRatioScript(2),
      ]);
    },
  );

  test('spa mode allows the scripts the page has', () async {
    final scripts = await _scriptSrc(
      'spring.flutter.web.page.swipe-to-close=false\n'
      'spring.flutter.web.page.max-pixel-ratio=2\n',
    );
    expect(scripts, contains(WebPageHead.hashOf(WebPageHead.swipeScript)));
    expect(
      scripts,
      contains(WebPageHead.hashOf(WebPageHead.pixelRatioScript(2))),
    );
  });

  test('spa mode allows the script of wasm-allow-list', () async {
    final scripts = await _scriptSrc(
      'spring.flutter.web.page.wasm-allow-list.gecko=true\n',
    );
    expect(
      scripts,
      contains(WebPageHead.hashOf(WebPageLoader.wasmScript({'gecko': true}))),
    );
  });

  test('spa mode allows no script the page does not have', () async {
    final scripts = await _scriptSrc('');
    expect(scripts.where((source) => source.startsWith("'sha256-")), isEmpty);
  });
}
