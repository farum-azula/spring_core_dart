// The search index of spring.search.markdown in a build: a file per
// language that the SearchService reads as it would have built it; none
// with spring.search.prebuilt=false, for a location outside resources: or
// a language whose analyzer is the app's own; the files of a language gone
// are deleted; a missing Flutter asset directory is warned about; the main
// builder never embeds them.
import 'dart:convert';
import 'dart:typed_data';

import 'package:build_test/build_test.dart';
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_core_dart_generator/src/search_index_builder.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:spring_search_dart/spring_search_dart.dart';
import 'package:test/test.dart';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => springApplication.run(args);
''';

String _config({
  String extra = '',
  String location = 'resources:docs/**/*.md',
}) =>
    '''
spring:
  search:
$extra    markdown:
      - location: $location
        exclude: ['**/contents*.md']
        link: /docs/{path}
''';

Map<String, Object> _sources({String? config, String? pubspec}) => {
  'pkg|lib/main.dart': _main,
  'pkg|lib/resources/application.yml': config ?? _config(),
  'pkg|lib/resources/docs/beans.md':
      '# Beans\n\nA bean.\n\n## Scopes\n\nSingleton scopes.',
  'pkg|lib/resources/docs/beans.ja.md': '# ビーン\n\nビーンです。',
  'pkg|lib/resources/docs/contents.md': '- [Beans](beans.md)',
  'pkg|pubspec.yaml': ?pubspec,
};

final class _Memory implements SearchIndexOutput {
  _Memory([Map<String, String>? files]) : files = files ?? {};

  final Map<String, String> files;

  @override
  Future<void> write(String package, String path, String content) async =>
      files[path] = content;

  @override
  Future<void> deleteOthers(
    String package,
    String directory,
    Set<String> kept,
  ) async => files.removeWhere(
    (path, _) => path.startsWith(directory) && !kept.contains(path),
  );
}

Future<List<String>> _build(
  _Memory output,
  Map<String, Object> sources,
) async {
  final logs = <String>[];
  final readerWriter = TestReaderWriter(rootPackage: 'pkg');
  await readerWriter.testing.loadIsolateSources();
  await testBuilder(
    SearchIndexBuilder(output: output),
    sources,
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    onLog: (record) => logs.add(record.message),
  );
  return logs;
}

const _en = 'lib/resources/spring_gen/search/en.json';
const _ja = 'lib/resources/spring_gen/search/ja.json';

final class _Files implements ResourceLoader {
  _Files(this.files);

  final Map<String, String> files;

  @override
  Resource getResource(String location) {
    final path = 'lib/resources/${location.replaceFirst('resources:', '')}';
    final text = files[path];
    return text == null
        ? DescriptiveResource(location)
        : ByteArrayResource(utf8.encode(text));
  }
}

final class _NoPages implements ResourcePatternResolver {
  @override
  List<Resource> getResources(String locationPattern) => [
    // The service lists the pages' languages; it does not read them.
    for (final path in ['docs/beans.md', 'docs/beans.ja.md']) _Listed(path),
  ];

  @override
  Resource getResource(String location) => DescriptiveResource(location);
}

final class _Listed extends AbstractResource implements ContextResource {
  _Listed(this.pathWithinContext);

  @override
  final String pathWithinContext;

  @override
  String get description => pathWithinContext;

  @override
  bool exists() => true;

  @override
  Future<Uint8List> readAsBytes() =>
      throw StateError('$pathWithinContext was read');
}

void main() {
  test('a file per language, which the service reads', () async {
    final output = _Memory();
    await _build(output, _sources());
    expect(output.files.keys, unorderedEquals([_en, _ja]));
    final service = SearchService(
      [
        MarkdownSearchSource(
          _NoPages(),
          location: 'resources:docs/**/*.md',
          exclude: const ['**/contents*.md'],
          link: '/docs/{path}',
        ),
      ],
      files: SearchIndexFiles(_Files(output.files)),
    );
    final hits = await service.search('scopes');
    expect(hits.single.document.link, '/docs/beans#scopes');
    expect(hits.single.snippet('body').text, 'Singleton scopes.');
    expect(await service.search('ビーン', language: 'ja'), isNotEmpty);
  });

  test('none with prebuilt=false; the files before are deleted', () async {
    final output = _Memory({_en: '{}', _ja: '{}'});
    await _build(
      output,
      _sources(config: _config(extra: '    prebuilt: false\n')),
    );
    expect(output.files, isEmpty);
  });

  test('none for a location outside resources:', () async {
    final output = _Memory();
    await _build(
      output,
      _sources(config: _config(location: 'asset:docs/**/*.md')),
    );
    expect(output.files, isEmpty);
  });

  test("none for a language whose analyzer is the app's own", () async {
    final output = _Memory();
    await _build(
      output,
      _sources(config: _config(extra: '    analyzers: { ja: kuromoji }\n')),
    );
    expect(output.files.keys, [_en]);
  });

  test('a missing Flutter asset directory is warned about', () async {
    final logs = await _build(
      _Memory(),
      _sources(pubspec: 'name: pkg\nflutter:\n  assets:\n    - lib/x/\n'),
    );
    expect(
      logs,
      contains(contains('    - lib/resources/spring_gen/search/')),
    );
    final quiet = await _build(
      _Memory(),
      _sources(
        pubspec:
            'name: pkg\nflutter:\n  assets:\n'
            '    - lib/resources/spring_gen/search/\n',
      ),
    );
    expect(quiet, isNot(contains(contains('spring_gen/search'))));
  });

  test('the main builder does not embed the files', () async {
    final readerWriter = TestReaderWriter(
      rootPackage: 'pkg',
      flattenOutput: true,
    );
    await readerWriter.testing.loadIsolateSources();
    final result = await testBuilder(
      SpringBuilder(),
      {..._sources(), 'pkg|$_en': '{"format": 1}'},
      rootPackage: 'pkg',
      readerWriter: readerWriter,
      flattenOutput: true,
    );
    final module = result.readerWriter.testing.readString(
      result.outputs.singleWhere(
        (o) => o.path == 'lib/spring_gen/main.spring.dart',
      ),
    );
    expect(module, contains("r'docs/beans.md'"));
    expect(module, isNot(contains('spring_gen/search')));
  });
}
