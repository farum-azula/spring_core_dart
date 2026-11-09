// What the generator runs: the index file of each language from the pages,
// which the service reads as it would have built it, without reading a
// page; no file for a language whose analyzer is the app's own, none for a
// location outside resources:; the command line the generator calls.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/spring_search_dart.dart';
import 'package:test/test.dart';

const _texts = {
  'docs/beans.md': '# Beans\n\nA bean.\n\n## Scopes\n\nSingleton scopes.',
  'docs/beans.ja.md': '# ビーン\n\nビーンです。',
  'docs/contents.md': '- [Beans](beans.md)',
  'application.yml': 'a: 1',
};

const List<MarkdownEntry> _markdown = [
  (
    location: 'resources:docs/**/*.md',
    exclude: ['**/contents*.md'],
    link: '/docs/{path}',
  ),
];

final class _Files implements ResourceLoader {
  _Files(this.files);

  final Map<String, String> files;

  @override
  Resource getResource(String location) {
    final language = location.split('/').last.replaceAll('.json', '');
    final text = files[language];
    return text == null
        ? DescriptiveResource(location)
        : ByteArrayResource(utf8.encode(text));
  }
}

// The pages listed, never read: the service lists their languages only.
final class _Listed implements ResourcePatternResolver {
  @override
  List<Resource> getResources(String locationPattern) => [
    for (final path in ['docs/beans.md', 'docs/beans.ja.md']) _Page(path),
  ];

  @override
  Resource getResource(String location) => DescriptiveResource(location);
}

final class _Page extends AbstractResource implements ContextResource {
  _Page(this.pathWithinContext);

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
    final files = await SearchIndexWriter.build(
      texts: _texts,
      markdown: _markdown,
    );
    expect(files.keys, ['en', 'ja']);
    final service = SearchService(
      [
        MarkdownSearchSource(
          _Listed(),
          location: 'resources:docs/**/*.md',
          exclude: const ['**/contents*.md'],
          link: '/docs/{path}',
        ),
      ],
      files: SearchIndexFiles(_Files(files)),
    );
    final hits = await service.search('scopes');
    expect(hits.single.document.link, '/docs/beans#scopes');
    expect(hits.single.snippet('body').text, 'Singleton scopes.');
    expect(await service.search('ビーン', language: 'ja'), isNotEmpty);
  });

  test("no file for a language whose analyzer is the app's own", () async {
    final files = await SearchIndexWriter.build(
      texts: _texts,
      markdown: _markdown,
      analyzers: {'ja': 'kuromoji'},
    );
    expect(files.keys, ['en']);
  });

  test('none for a location outside resources:', () async {
    final files = await SearchIndexWriter.build(
      texts: _texts,
      markdown: const [
        (location: 'asset:docs/**/*.md', exclude: [], link: '/{path}'),
      ],
    );
    expect(files, isEmpty);
  });

  test(
    'the command line the generator runs',
    () async {
      final work = Directory.systemTemp.createTempSync('search_index');
      addTearDown(() => work.deleteSync(recursive: true));
      final request = File('${work.path}/request.json')
        ..writeAsStringSync(
          jsonEncode({
            'texts': _texts,
            'markdown': [
              {
                'location': 'resources:docs/**/*.md',
                'exclude': ['**/contents*.md'],
                'link': '/docs/{path}',
              },
            ],
            'analyzers': <String, String>{},
            'defaultLanguage': 'en',
          }),
        );
      final response = File('${work.path}/response.json');
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        'spring_search_dart:search_index',
        request.path,
        response.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final files = (jsonDecode(response.readAsStringSync()) as Map)
          .cast<String, String>();
      expect(files.keys, ['en', 'ja']);
      expect(
        (jsonDecode(files['en']!.split('\n').first) as Map)['analyzer'],
        'english',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
