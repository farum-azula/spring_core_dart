// Resource roots: a root added to resources: answers a path that is not
// embedded and joins its patterns; a protocol root lists the files of its
// patterns (asset:docs/**/*.md); removing a root takes it away.
import 'dart:convert';
import 'dart:typed_data';

import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

final class _Root implements ResourceRoot {
  _Root(this.files);

  final Map<String, String> files;

  @override
  Iterable<String> get paths => files.keys;

  @override
  Resource? resolve(String path) => switch (files[path]) {
    final text? => ByteArrayResource(
      Uint8List.fromList(utf8.encode(text)),
      description: 'root [$path]',
    ),
    null => null,
  };
}

void main() {
  final loader = DefaultResourceLoader();
  final patterns = PathMatchingResourcePatternResolver(resourceLoader: loader);

  test('resources: finds a file of an added root; patterns list it', () {
    final remove = Resources.addRoot(
      _Root({'roots-test/a.md': 'A', 'roots-test/b/c.md': 'C'}),
    );
    addTearDown(remove);
    expect(
      loader.getResource('resources:roots-test/a.md').readAsStringSync(),
      'A',
    );
    expect(
      [
        for (final r in patterns.getResources('resources:roots-test/**/*.md'))
          r.readAsStringSync(),
      ],
      ['A', 'C'],
    );
    remove();
    expect(loader.getResource('resources:roots-test/a.md').exists(), isFalse);
  });

  test('an embedded file wins over a root', () {
    Resources.registerAll({
      'roots-test/embedded.md': const EmbeddedResource.text('embedded'),
    }, owner: 'roots-test');
    final remove = Resources.addRoot(
      _Root({'roots-test/embedded.md': 'root'}),
    );
    addTearDown(remove);
    expect(
      loader.getResource('resources:roots-test/embedded.md').readAsStringSync(),
      'embedded',
    );
  });

  test('a protocol root lists the files of its patterns', () {
    final remove = Resources.addProtocolRoot(
      'test-asset:',
      _Root({'docs/a.md': 'A', 'docs/x/b.md': 'B', 'img/c.png': 'C'}),
    );
    addTearDown(remove);
    expect(
      [
        for (final r in patterns.getResources('test-asset:docs/**/*.md'))
          r.readAsStringSync(),
      ],
      ['A', 'B'],
    );
  });
}
