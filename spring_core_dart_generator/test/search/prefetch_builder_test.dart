// spring.resources.prefetch in a build: the files of its locations in one
// file, a line per piece; none without locations (the one before deleted);
// a missing Flutter asset directory is warned about.
import 'dart:convert';

import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/prefetch_builder.dart';
import 'package:spring_core_dart_generator/src/search_index_builder.dart';
import 'package:test/test.dart';

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

Map<String, Object> _sources(String config, {String? pubspec}) => {
  'pkg|lib/resources/application.yml': config,
  'pkg|lib/resources/content/docs/a.md': '# A',
  'pkg|lib/resources/content/docs/a.ja.md': '# エー',
  'pkg|lib/resources/content/notes.txt': 'notes',
  'pkg|pubspec.yaml': ?pubspec,
};

Future<List<String>> _build(_Memory output, Map<String, Object> sources) async {
  final logs = <String>[];
  final readerWriter = TestReaderWriter(rootPackage: 'pkg');
  await readerWriter.testing.loadIsolateSources();
  await testBuilder(
    PrefetchBuilder(output: output),
    sources,
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    onLog: (record) => logs.add(record.message),
  );
  return logs;
}

void main() {
  test('the files of the locations in one file, a line per piece', () async {
    final output = _Memory();
    await _build(
      output,
      _sources(
        "spring:\n  resources:\n    prefetch:\n      locations: ['content/**/*.md']\n",
      ),
    );
    final lines = LineSplitter.split(output.files[PrefetchBuilder.file]!);
    expect(jsonDecode(lines.first), {'format': 1, 'files': 2});
    expect(
      {for (final line in lines.skip(1)) ...jsonDecode(line) as Map},
      {'content/docs/a.ja.md': '# エー', 'content/docs/a.md': '# A'},
    );
  });

  test('no locations: no file, the one before deleted', () async {
    final output = _Memory({PrefetchBuilder.file: 'before'});
    await _build(output, _sources('spring:\n  application:\n    name: x\n'));
    expect(output.files, isEmpty);
  });

  test('a missing Flutter asset directory is warned about', () async {
    final logs = await _build(
      _Memory(),
      _sources(
        'spring.resources.prefetch.locations: content/**\n',
        pubspec: 'name: pkg\nflutter:\n  assets:\n    - lib/x/\n',
      ),
    );
    expect(logs, contains(contains('    - ${PrefetchBuilder.directory}')));
  });
}
