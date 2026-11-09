// The Markdown source reads the files of one language: Japanese reads the
// .ja.md files and, for a page without one, the default language's file,
// never the English file of a translated page.
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'package:spring_search_dart/spring_search_dart.dart';
import 'package:test/test.dart';

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

final class _Files implements ResourcePatternResolver {
  _Files(this.files);

  final List<Resource> files;

  @override
  List<Resource> getResources(String locationPattern) => files;

  @override
  Resource getResource(String location) => throw UnimplementedError();
}

void main() {
  test('Japanese reads its own files and the untranslated ones', () async {
    final reads = <String>[];
    final source = MarkdownSearchSource(
      _Files([
        _File('pages/start.md', '# Start\n\nHello.', reads),
        _File('pages/start.ja.md', '# はじめに\n\nこんにちは。', reads),
        _File('pages/beans.md', '# Beans\n\nA bean.', reads),
      ]),
      location: 'resources:pages/**/*.md',
    );
    expect(source.languages, {'en', 'ja'});
    final titles = [
      await for (final d in source.documentsIn('ja')) d.fields['title'],
    ];
    expect(titles, unorderedEquals(['はじめに', 'Beans']));
    expect(reads, unorderedEquals(['pages/start.ja.md', 'pages/beans.md']));
  });
}
