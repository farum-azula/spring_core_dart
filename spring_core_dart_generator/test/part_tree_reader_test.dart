// The grammar of derived query names without the analyzer: what the language
// server uses to read `findByTitleAndYearGreaterThan`. The build runs the
// same code through PartTreeParser (data_query_test.dart).
import 'package:spring_core_dart_generator/src/part_tree.dart';
import 'package:spring_core_dart_generator/src/part_tree_reader.dart';
import 'package:test/test.dart';

final class _Property implements PartTreeProperty {
  _Property(
    this.name, {
    this.isMappedCollection = false,
    this.isString = false,
  });

  @override
  final String name;
  @override
  final bool isMappedCollection;
  @override
  final bool isString;
}

final class _Entity implements PartTreeEntity {
  _Entity(this.name, this.properties);

  @override
  final String name;
  @override
  final List<_Property> properties;

  @override
  _Property? property(String name) {
    for (final p in properties) {
      if (p.name == name) {
        return p;
      }
    }
    return null;
  }

  @override
  Iterable<_Property> get columns =>
      properties.where((p) => !p.isMappedCollection);
}

final _book = _Entity('Book', [
  _Property('id'),
  _Property('title', isString: true),
  _Property('year'),
  _Property('inStock'),
  _Property('lines', isMappedCollection: true),
]);

PartTreeModel _parse(String name) => const PartTreeReader().parse(name, _book);

void main() {
  test('subject kinds, Distinct and Top', () {
    expect(_parse('findByTitle').subject.kind, SubjectKind.find);
    expect(_parse('countByYear').subject.kind, SubjectKind.count);
    expect(_parse('existsByTitle').subject.kind, SubjectKind.exists);
    expect(_parse('deleteByYear').subject.kind, SubjectKind.delete);
    final top = _parse('findDistinctTop5ByYear').subject;
    expect(top.maxResults, 5);
    expect(top.distinct, isTrue);
  });

  test('parts, operators and parameter count', () {
    final tree = _parse('findByTitleContainingAndYearBetweenOrInStockTrue');
    expect(tree.predicate, hasLength(2));
    expect(
      [for (final p in tree.parts) '${p.property}:${p.kind.name}'],
      [
        'title:containing',
        'year:between',
        'inStock:isTrue',
      ],
    );
    expect(tree.parameterCount, 3);
  });

  test('OrderBy and IgnoreCase', () {
    final tree = _parse('findByTitleIgnoreCaseOrderByYearDescTitleAsc');
    expect(tree.parts.single.ignoreCase, isTrue);
    expect(
      [for (final o in tree.sort) '${o.property}:${o.descending}'],
      [
        'year:true',
        'title:false',
      ],
    );
  });

  test('an empty predicate matches everything', () {
    expect(_parse('findAllBy').predicate, isEmpty);
    expect(_parse('findByOrderByYear').sort.single.property, 'year');
  });

  test('an unknown property is a problem with the name and a hint', () {
    try {
      _parse('findByTitelContaining');
      fail('should throw');
    } on QueryProblem catch (problem) {
      expect(problem.property, 'titel');
      expect(problem.reason, contains("did you mean 'title'?"));
    }
  });

  test('a collection and a nested path are refused', () {
    expect(
      () => _parse('findByLines'),
      throwsA(
        isA<QueryProblem>().having((p) => p.property, 'property', 'lines'),
      ),
    );
    expect(
      () => _parse('findByAuthorName'),
      throwsA(isA<QueryProblem>()),
    );
  });

  test('isDerivedQuery tells a derived name from another', () {
    expect(PartTreeReader.isDerivedQuery('findByTitle'), isTrue);
    expect(PartTreeReader.isDerivedQuery('findAllByYear'), isTrue);
    expect(PartTreeReader.isDerivedQuery('cards'), isFalse);
    expect(PartTreeReader.isDerivedQuery('save'), isFalse);
    expect(PartTreeReader.isDerivedQuery('watchByTitle'), isTrue);
    expect(PartTreeReader.isDerivedQuery('changesAllBy'), isTrue);
    // A prefix is a word: what follows it starts with an upper-case letter.
    expect(PartTreeReader.isDerivedQuery('watchmanByTitle'), isFalse);
    expect(PartTreeReader.isDerivedQuery('watch'), isFalse);
  });

  test('prefixOf is the first word of a derived name', () {
    expect(PartTreeReader.prefixOf('findTop3ByTitle'), 'find');
    expect(PartTreeReader.prefixOf('watchByTitle'), 'watch');
    expect(PartTreeReader.prefixOf('changesAllBy'), 'changes');
    expect(PartTreeReader.prefixOf('save'), isNull);
  });
}
