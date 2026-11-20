// What the caches build on: a CacheStore of bytes by path (in memory here),
// and the description of a class found by its name in the source, which
// reads a value kept on disk back as that class.
import 'dart:convert';

import 'package:spring_core_dart/beans.dart';
import 'package:spring_core_dart/core.dart';
import 'package:test/test.dart';

final class _Hero {
  _Hero(this.name);

  final String name;
}

void main() {
  test('InMemoryCacheStore: bytes by path, folders by prefix', () async {
    final store = InMemoryCacheStore();
    await store.write('spring/caches/a/1.json', utf8.encode('one'));
    await store.write('spring/caches/a/2.json', utf8.encode('two'));
    await store.write('spring/resources/x/data', [1, 2, 3]);
    expect(utf8.decode((await store.read('spring/caches/a/1.json'))!), 'one');
    expect(await store.size('spring/resources/x/data'), 3);
    expect(
      await store.list('spring/caches'),
      ['spring/caches/a/1.json', 'spring/caches/a/2.json'],
    );
    await store.delete('spring/caches');
    expect(await store.list('spring/caches'), isEmpty);
    expect(await store.list(''), ['spring/resources/x/data']);
    expect(await store.read('nothing'), isNull);
  });

  test('a class found by its name in the source, here or in the parent', () {
    final parent = Introspector()
      ..register(const Introspection<_Hero>(className: 'Hero'));
    final child = Introspector(parent: parent);
    final hero = child.byClassName('Hero')!;
    expect(hero.type, _Hero);
    expect(hero.classType, isA<ClassType<_Hero>>());
    expect(hero.listOf([_Hero('Lina')]), isA<List<_Hero>>());
    expect(hero.setOf([_Hero('Doom')]), isA<Set<_Hero>>());
    expect(hero.mapOf({'mid': _Hero('Lina')}), isA<Map<String, _Hero>>());
    expect(child.byClassName('Villain'), isNull);
  });
}
