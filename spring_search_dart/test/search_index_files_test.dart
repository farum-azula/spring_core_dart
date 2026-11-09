// The index the build writes: read back, it finds what the built one finds
// (scores, prefixes, typos, phrases, highlights, snippets); the service
// reads it instead of the pages when it matches the analyzer and the
// Markdown sources, and builds the index itself when it does not.
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/spring_search_dart.dart';
import 'package:test/test.dart';

const _pages = {
  'pages/beans.md':
      '# Beans\n\nA bean is an object the container makes.\n\n'
      '## Scopes\n\nSingleton and prototype scopes of beans.\n\n'
      '## Binding\n\nThe binding of configuration properties.',
  'pages/context.md':
      '# Application context\n\nThe context holds the beans.\n\n'
      '## Events\n\nPublishing events to listeners.',
  'pages/beans.ja.md': '# ビーン\n\nビーンはコンテナが作るオブジェクトです。',
};

final class _File extends ByteArrayResource implements ContextResource {
  _File(this.pathWithinContext, String text, this.reads)
    : super(Uint8List.fromList(utf8.encode(text)));

  @override
  final String pathWithinContext;
  final List<String> reads;

  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    reads.add(pathWithinContext);
    return super.readAsString(encoding: encoding);
  }
}

// The pages, and the index files at their resources: locations.
final class _Resources implements ResourcePatternResolver {
  _Resources(this.indexes);

  final Map<String, String> indexes;
  final reads = <String>[];

  @override
  List<Resource> getResources(String locationPattern) => [
    for (final MapEntry(:key, :value) in _pages.entries)
      _File(key, value, reads),
  ];

  @override
  Resource getResource(String location) => switch (indexes[location]) {
    final text? => _File(location, text, reads),
    null => DescriptiveResource(location),
  };
}

MarkdownSearchSource _source(ResourcePatternResolver resources) =>
    MarkdownSearchSource(
      resources,
      location: 'resources:pages/**/*.md',
      link: '/docs/{path}',
    );

Future<String> _file(
  String language, {
  SearchAnalyzer? analyzer,
  String link = '/docs/{path}',
}) async {
  final source = MarkdownSearchSource(
    _Resources(const {}),
    location: 'resources:pages/**/*.md',
    link: link,
  );
  final used = analyzer ?? SearchAnalyzers().of(language);
  return SearchIndexFiles.encode(
    language: language,
    analyzer: used,
    sources: [source],
    index: SearchIndex.build(
      await source.documentsIn(language).toList(),
      used,
    ),
  );
}

String _hits(List<SearchHit> hits) => [
  for (final hit in hits)
    '${hit.document.id} ${hit.score.toStringAsFixed(6)} '
            '${hit.highlights} ${hit.snippet('body').text}'
        .trim(),
].join('\n');

void main() {
  test('read back, the index finds what the built one finds', () async {
    final analyzer = SearchAnalyzers().of('en');
    final documents = await _source(
      _Resources(const {}),
    ).documentsIn('en').toList();
    final built = SearchIndex.build(documents, analyzer);
    final read = SearchIndex.fromJson(
      jsonDecode(jsonEncode(built.toJson())) as Map<String, Object?>,
      analyzer,
    );
    expect(read.termCount, built.termCount);
    for (final query in [
      'bean',
      'bea',
      'scops',
      '"configuration properties"',
      'context events',
      'singleton OR listeners',
      'binding',
    ]) {
      final parsed = SearchQuery.parse(query);
      expect(
        _hits(read.search(parsed)),
        _hits(built.search(parsed)),
        reason: query,
      );
    }
    expect(read.search(SearchQuery.parse('bean')), isNotEmpty);
  });

  test('the service reads the file, not the pages', () async {
    final resources = _Resources({
      SearchIndexFiles.locationOf('en'): await _file('en'),
      SearchIndexFiles.locationOf('ja'): await _file('ja'),
    });
    final service = SearchService(
      [_source(resources)],
      files: SearchIndexFiles(resources),
    );
    final hits = await service.search('scopes');
    expect(hits.first.document.link, '/docs/beans#scopes');
    expect(await service.search('ビーン', language: 'ja'), isNotEmpty);
    expect(resources.reads, [
      SearchIndexFiles.locationOf('en'),
      SearchIndexFiles.locationOf('ja'),
    ]);
  });

  test('another analyzer or other sources: the pages are read', () async {
    for (final file in [
      await _file('en', analyzer: SearchAnalyzer.standard),
      await _file('en', link: '/other/{path}'),
    ]) {
      final resources = _Resources({SearchIndexFiles.locationOf('en'): file});
      final service = SearchService(
        [_source(resources)],
        files: SearchIndexFiles(resources),
      );
      expect(
        (await service.search('scopes')).first.document.link,
        '/docs/beans#scopes',
      );
      expect(resources.reads, contains('pages/beans.md'));
    }
  });

  test('a source of its own: the index is built from all of them', () async {
    final resources = _Resources({
      SearchIndexFiles.locationOf('en'): await _file('en'),
    });
    final service = SearchService(
      [_source(resources), _Notes()],
      files: SearchIndexFiles(resources),
    );
    expect(await service.search('note'), hasLength(1));
    expect(await service.search('scopes'), isNotEmpty);
  });
}

final class _Notes implements SearchDocumentSource {
  @override
  Stream<SearchDocument> documents() => Stream.value(
    const SearchDocument(id: 'note', fields: {'title': 'A note'}),
  );
}
