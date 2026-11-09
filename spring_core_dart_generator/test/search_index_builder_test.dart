// The search index of spring.search.markdown in a build: the builder hands
// the pages and the settings to the app's spring_search_dart and writes the
// file of each language it gets; nothing with spring.search.prebuilt=false;
// the files of a language gone are deleted, and kept when making them
// failed; a missing Flutter asset directory is warned about; the main
// builder never embeds them. (What the files hold, and that the search reads
// them: spring_search_dart's tests.)
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/search_index_builder.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
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

final _requests = <Map<String, Object?>>[];

Future<Map<String, String>?> _runner(
  String package,
  Map<String, Object?> request,
) async {
  _requests.add(request);
  return {'en': '{"en": 1}', 'ja': '{"ja": 1}'};
}

Future<List<String>> _build(
  _Memory output,
  Map<String, Object> sources, {
  SearchIndexRunner runner = _runner,
}) async {
  final logs = <String>[];
  final readerWriter = TestReaderWriter(rootPackage: 'pkg');
  await readerWriter.testing.loadIsolateSources();
  await testBuilder(
    SearchIndexBuilder(output: output, runner: runner),
    sources,
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    onLog: (record) => logs.add(record.message),
  );
  return logs;
}

const _en = 'lib/resources/spring_gen/search/en.json';
const _ja = 'lib/resources/spring_gen/search/ja.json';

void main() {
  setUp(_requests.clear);

  test(
    'the pages and the settings go to the runner; its files are written',
    () async {
      final output = _Memory({'lib/resources/spring_gen/search/de.json': '{}'});
      await _build(
        output,
        _sources(config: _config(extra: '    analyzers: { ja: standard }\n')),
      );
      expect(output.files, {_en: '{"en": 1}', _ja: '{"ja": 1}'});
      final request = _requests.single;
      expect(
        (request['texts']! as Map).keys,
        unorderedEquals([
          'docs/beans.md',
          'docs/beans.ja.md',
          'docs/contents.md',
        ]),
      );
      expect(request['markdown'], [
        {
          'location': 'resources:docs/**/*.md',
          'exclude': ['**/contents*.md'],
          'link': '/docs/{path}',
        },
      ]);
      expect(request['analyzers'], {'ja': 'standard'});
      expect(request['defaultLanguage'], 'en');
    },
  );

  test('none with prebuilt=false; the files before are deleted', () async {
    final output = _Memory({_en: '{}', _ja: '{}'});
    await _build(
      output,
      _sources(config: _config(extra: '    prebuilt: false\n')),
    );
    expect(output.files, isEmpty);
    expect(_requests, isEmpty);
  });

  test('when the runner fails, the files before stay', () async {
    final output = _Memory({_en: 'before'});
    await _build(output, _sources(), runner: (_, _) async => null);
    expect(output.files, {_en: 'before'});
  });

  test('a missing Flutter asset directory is warned about', () async {
    final logs = await _build(
      _Memory(),
      _sources(pubspec: 'name: pkg\nflutter:\n  assets:\n    - lib/x/\n'),
    );
    expect(logs, contains(contains('    - lib/resources/spring_gen/search/')));
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
