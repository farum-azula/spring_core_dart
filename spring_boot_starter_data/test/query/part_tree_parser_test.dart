import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

import 'support/entities.dart';

void main() {
  const parser = PartTreeParser(repositoryName: 'BookRepository');
  final entity = bookEntity();

  PartTree parse(String name) => parser.parse(name, entity);

  Part only(String name) => parse(name).parts.single;

  void validate(
    String name,
    List<BeanParameter> params, {
    TypeInfo<Object?> returnType = const ListType<Book>(ClassType<Book>()),
    bool isFuture = true,
  }) => parser.validate(
    parse(name),
    entity,
    params,
    returnType: returnType,
    isFuture: isFuture,
  );

  Matcher throwsQuery(String message) => throwsA(
    isA<QueryCreationException>().having(
      (e) => e.message,
      'message',
      contains(message),
    ),
  );

  group('subject', () {
    const prefixes = {
      'find': SubjectKind.find,
      'read': SubjectKind.find,
      'get': SubjectKind.find,
      'query': SubjectKind.find,
      'search': SubjectKind.find,
      'stream': SubjectKind.find,
      'count': SubjectKind.count,
      'exists': SubjectKind.exists,
      'delete': SubjectKind.delete,
      'remove': SubjectKind.delete,
    };
    prefixes.forEach((prefix, kind) {
      test('$prefix is $kind', () {
        final tree = parse('${prefix}ByTitle');
        expect(tree.subject, Subject(kind));
        expect(tree.parts.single.property, 'title');
      });
    });

    test('First and Top, with and without a number', () {
      expect(parse('findFirstByTitle').subject.maxResults, 1);
      expect(parse('findTopByTitle').subject.maxResults, 1);
      expect(parse('findTop10ByTitle').subject.maxResults, 10);
      expect(parse('findFirst3ByTitle').subject.maxResults, 3);
      expect(parse('findByTitle').subject.maxResults, isNull);
    });

    test('words after the prefix do not make a limit', () {
      expect(parse('findBooksByTitle').subject.maxResults, isNull);
      expect(parse('findFirstBooksByTitle').subject.maxResults, 1);
    });

    test('Distinct anywhere in the subject', () {
      expect(parse('findDistinctByTitle').subject.distinct, isTrue);
      expect(
        parse('findDistinctTop2ByTitle').subject,
        const Subject(SubjectKind.find, maxResults: 2, distinct: true),
      );
      expect(
        parse('findTop2DistinctByTitle').subject,
        const Subject(SubjectKind.find, maxResults: 2, distinct: true),
      );
      expect(
        parse('countDistinctByTitle').subject,
        const Subject(SubjectKind.count, distinct: true),
      );
      expect(parse('findByTitle').subject.distinct, isFalse);
    });

    test('other words between the prefix and By are ignored', () {
      expect(
        parse('findBooksByTitle').subject,
        const Subject(SubjectKind.find),
      );
      expect(parse('findAllByTitle').parts.single.property, 'title');
      expect(parse('getAllBooksByYear').parts.single.property, 'year');
    });

    test('a name without a prefix and By is not a derived query', () {
      expect(PartTreeParser.isDerivedQuery('findByTitle'), isTrue);
      expect(PartTreeParser.isDerivedQuery('findAllBooksByTitle'), isTrue);
      expect(PartTreeParser.isDerivedQuery('countBy'), isTrue);
      expect(PartTreeParser.isDerivedQuery('save'), isFalse);
      expect(PartTreeParser.isDerivedQuery('findAll'), isFalse);
      expect(PartTreeParser.isDerivedQuery('fetchByTitle'), isFalse);
      expect(PartTreeParser.isDerivedQuery('findbyTitle'), isFalse);
      expect(() => parse('findAll'), throwsQuery('not a derived query'));
      expect(() => parse('titleBy'), throwsQuery('not a derived query'));
    });
  });

  group('predicate', () {
    test('empty predicates match everything', () {
      expect(parse('findAllBy').predicate, isEmpty);
      expect(parse('findBy').predicate, isEmpty);
      expect(parse('countBy').predicate, isEmpty);
      final tree = parse('findAllByOrderByTitleAsc');
      expect(tree.predicate, isEmpty);
      expect(tree.sort.orders.single.property, 'title');
    });

    test('And / Or precedence: AOrBAndC = A or (B and C)', () {
      final tree = parse('findByTitleOrYearAndPrice');
      expect(tree.predicate, hasLength(2));
      expect(tree.predicate[0].parts.map((p) => p.property), ['title']);
      expect(tree.predicate[1].parts.map((p) => p.property), [
        'year',
        'price',
      ]);
      final other = parse('findByTitleAndYearOrPrice');
      expect(other.predicate[0].parts.map((p) => p.property), [
        'title',
        'year',
      ]);
      expect(other.predicate[1].parts.map((p) => p.property), ['price']);
    });

    test('parameterCount and parts follow the name', () {
      final tree = parse('findByYearBetweenAndTitleOrInStockTrue');
      expect(tree.parts.map((p) => p.type), [
        PartType.between,
        PartType.simpleProperty,
        PartType.isTrue,
      ]);
      expect(tree.parameterCount, 3);
    });

    test('properties containing Or, And and keywords stay whole', () {
      for (final (name, property) in [
        ('OrderNumber', 'orderNumber'),
        ('Origin', 'origin'),
        ('Android', 'android'),
        ('Isbn', 'isbn'),
        ('InStock', 'inStock'),
        ('Notes', 'notes'),
        ('Between', 'between'),
        ('URL', 'URL'),
        ('Address', 'address'),
      ]) {
        final part = only('findBy$name');
        expect(part.property, property, reason: name);
        expect(part.type, PartType.simpleProperty, reason: name);
      }
    });

    test('names with Or/And inside properties combine with real ones', () {
      final tree = parse('findByOrderNumberAndOriginOrAndroidAndIsbn');
      expect(tree.predicate[0].parts.map((p) => p.property), [
        'orderNumber',
        'origin',
      ]);
      expect(tree.predicate[1].parts.map((p) => p.property), [
        'android',
        'isbn',
      ]);
      expect(
        parse('findByOrderNumberOrderByOrigin').sort.orders.single.property,
        'origin',
      );
    });

    test('keywords on properties named like keywords', () {
      expect(only('findByNotesNull').type, PartType.isNull);
      expect(only('findByNotesNotNull').type, PartType.isNotNull);
      expect(only('findByBetweenIn').type, PartType.in_);
      expect(only('findByBetweenIn').property, 'between');
      expect(only('findByInStockNot').type, PartType.negatingSimpleProperty);
      expect(only('findByURLContaining').property, 'URL');
    });

    test('every keyword and alias', () {
      const cases = {
        'YearBetween': PartType.between,
        'YearIsBetween': PartType.between,
        'NotesIsNotNull': PartType.isNotNull,
        'NotesNotNull': PartType.isNotNull,
        'NotesIsNull': PartType.isNull,
        'NotesNull': PartType.isNull,
        'YearLessThan': PartType.lessThan,
        'YearIsLessThan': PartType.lessThan,
        'YearBefore': PartType.lessThan,
        'YearIsBefore': PartType.lessThan,
        'YearLessThanEqual': PartType.lessThanEqual,
        'YearIsLessThanEqual': PartType.lessThanEqual,
        'YearGreaterThan': PartType.greaterThan,
        'YearIsGreaterThan': PartType.greaterThan,
        'YearAfter': PartType.greaterThan,
        'YearIsAfter': PartType.greaterThan,
        'YearGreaterThanEqual': PartType.greaterThanEqual,
        'YearIsGreaterThanEqual': PartType.greaterThanEqual,
        'TitleNotLike': PartType.notLike,
        'TitleIsNotLike': PartType.notLike,
        'TitleLike': PartType.like,
        'TitleIsLike': PartType.like,
        'TitleStartingWith': PartType.startingWith,
        'TitleIsStartingWith': PartType.startingWith,
        'TitleStartsWith': PartType.startingWith,
        'TitleEndingWith': PartType.endingWith,
        'TitleIsEndingWith': PartType.endingWith,
        'TitleEndsWith': PartType.endingWith,
        'TitleNotContaining': PartType.notContaining,
        'TitleIsNotContaining': PartType.notContaining,
        'TitleNotContains': PartType.notContaining,
        'TitleContaining': PartType.containing,
        'TitleIsContaining': PartType.containing,
        'TitleContains': PartType.containing,
        'YearNotIn': PartType.notIn,
        'YearIsNotIn': PartType.notIn,
        'YearIn': PartType.in_,
        'YearIsIn': PartType.in_,
        'InStockTrue': PartType.isTrue,
        'InStockIsTrue': PartType.isTrue,
        'InStockFalse': PartType.isFalse,
        'InStockIsFalse': PartType.isFalse,
        'YearNot': PartType.negatingSimpleProperty,
        'YearIsNot': PartType.negatingSimpleProperty,
        'YearIs': PartType.simpleProperty,
        'YearEquals': PartType.simpleProperty,
        'Year': PartType.simpleProperty,
      };
      cases.forEach((source, type) {
        final part = only('findBy$source');
        expect(part.type, type, reason: source);
        expect(
          part.property,
          anyOf('title', 'year', 'notes', 'inStock'),
          reason: source,
        );
      });
    });
  });

  group('ignore case', () {
    test('IgnoreCase and IgnoringCase on one part', () {
      expect(only('findByTitleIgnoreCase').ignoreCase, isTrue);
      expect(only('findByTitleIgnoringCase').ignoreCase, isTrue);
      expect(only('findByTitleContainingIgnoreCase').type, PartType.containing);
      expect(only('findByTitleContainingIgnoreCase').ignoreCase, isTrue);
      expect(only('findByTitle').ignoreCase, isFalse);
      final tree = parse('findByTitleIgnoreCaseAndOrigin');
      expect(tree.parts.map((p) => p.ignoreCase), [true, false]);
    });

    test('AllIgnoreCase applies to the String parts only', () {
      for (final suffix in ['AllIgnoreCase', 'AllIgnoringCase']) {
        final tree = parse('findByTitleAndYearAndOrigin$suffix');
        expect(tree.parts.map((p) => p.ignoreCase), [true, false, true]);
      }
      final tree = parse('findByTitleAllIgnoreCaseOrderByYear');
      expect(tree.parts.single.ignoreCase, isTrue);
      expect(tree.sort.orders.single.property, 'year');
    });

    test('AllIgnoreCase leaves argument-less parts alone', () {
      final tree = parse('findByNotesNullAndTitleAllIgnoreCase');
      expect(tree.parts.map((p) => p.ignoreCase), [false, true]);
    });
  });

  group('order by', () {
    test('several properties and directions', () {
      final sort = parse(
        'findByYearOrderByYearDescTitleAscOriginAscAndroid',
      ).sort;
      expect(
        sort.orders.map((o) => (o.property, o.direction)),
        [
          ('year', Direction.desc),
          ('title', Direction.asc),
          ('origin', Direction.asc),
          ('android', Direction.asc),
        ],
      );
    });

    test('no direction is ascending; Desc-like property names survive', () {
      expect(
        parse('findAllByOrderByYear').sort.orders.single.direction,
        Direction.asc,
      );
      expect(
        parse('findAllByOrderByOrderNumberDesc').sort.orders.single,
        const SortOrder.desc('orderNumber'),
      );
    });

    test('no OrderBy is unsorted', () {
      expect(parse('findByTitle').sort.isSorted, isFalse);
    });

    test('unknown property or two OrderBy are errors', () {
      expect(() => parse('findAllByOrderByTitel'), throwsQuery("'titel'"));
      expect(
        () => parse('findAllByOrderByTitleOrderByYear'),
        throwsQuery('more than one'),
      );
      expect(
        () => parse('findAllByOrderByChapters'),
        throwsQuery('child entities'),
      );
    });
  });

  group('property errors', () {
    test('unknown property with a suggestion and the property list', () {
      expect(
        () => parse('findByTitel'),
        throwsQuery(
          "No property 'titel' found for type 'Book'; did you mean "
          "'title'?",
        ),
      );
      expect(() => parse('findByTitel'), throwsQuery('Available properties'));
      expect(
        () => parse('findByTitel'),
        throwsQuery('BookRepository.findByTitel'),
      );
    });

    test('no suggestion when nothing is close', () {
      expect(
        () => parse('findByZzzzzz'),
        throwsA(
          isA<QueryCreationException>().having(
            (e) => e.message,
            'message',
            allOf(contains("No property 'zzzzzz'"), isNot(contains('did you'))),
          ),
        ),
      );
    });

    test('the exception names the method and the repository', () {
      try {
        parse('findByNope');
        fail('expected an exception');
      } on QueryCreationException catch (e) {
        expect(e.methodName, 'findByNope');
        expect(e.repositoryName, 'BookRepository');
        expect(e, isA<InvalidDataAccessApiUsageException>());
      }
    });

    test('a mapped collection is not queryable', () {
      expect(
        () => parse('findByChapters'),
        throwsQuery('derived queries stay within the columns'),
      );
    });

    test('nested paths are not supported', () {
      expect(() => parse('findByAddressCity'), throwsQuery('nested'));
      expect(() => parse('findByAddress_City'), throwsQuery('nested'));
      expect(() => parse('findByAddressCityContaining'), throwsQuery('nested'));
    });

    test('a property is never taken from the middle of a part', () {
      expect(() => parse('findByYearTitle'), throwsQuery('nested'));
    });
  });

  group('validate parameters', () {
    test('the example of the docs', () {
      validate(
        'findTop5ByTitleContainingIgnoreCaseAndYearGreaterThanOrderByYearDesc',
        [param('title', string), param('year', integer)],
      );
    });

    test('wrong parameter count', () {
      expect(
        () => validate('findByTitle', []),
        throwsQuery('needs 1 parameter'),
      );
      expect(
        () => validate('findByTitle', [param('a', string), param('b', string)]),
        throwsQuery('declares 2'),
      );
      expect(
        () => validate('findByYearBetween', [param('a', integer)]),
        throwsQuery('needs 2'),
      );
      validate('findByYearBetween', [param('a', integer), param('b', integer)]);
      validate('findByNotesNull', []);
      validate('findByInStockTrue', []);
      validate('findAllByOrderByTitleAsc', []);
    });

    test('wrong types', () {
      expect(
        () => validate('findByTitle', [param('t', integer)]),
        throwsQuery('does not fit'),
      );
      expect(
        () => validate('findByYear', [param('y', string)]),
        throwsQuery('does not fit'),
      );
      expect(
        () => validate('findByTitleContaining', [param('t', integer)]),
        throwsQuery('must be a String'),
      );
      expect(
        () => validate('findByYearContaining', [param('t', string)]),
        throwsQuery('needs a String property'),
      );
    });

    test('compatible types', () {
      validate('findByYear', [
        param('y', const ClassType<int>(nullable: true)),
      ]);
      validate('findByYear', [param('y', const ClassType<num>())]);
      validate('findByPrice', [param('p', integer)]);
      validate('findByPrice', [param('p', const ClassType<double>())]);
      validate('findByYear', [param('y', const DynamicType())]);
      validate('findByYear', [param('y', const ClassType<Object>())]);
      validate('findByPublished', [param('d', const ClassType<DateTime>())]);
      validate('findByAuthorId', [param('a', integer)]);
      validate('findByAuthorId', [param('a', const ClassType<Object>())]);
      validate('findByTitleLike', [param('t', string)]);
    });

    test('ignoreCase only on String properties', () {
      expect(
        () => validate('findByYearIgnoreCase', [param('y', integer)]),
        throwsQuery('IgnoreCase needs a String'),
      );
      validate('findByTitleIgnoreCase', [param('t', string)]);
      validate('findByYearAndTitleAllIgnoreCase', [
        param('y', integer),
        param('t', string),
      ]);
    });

    test('True and False only on bool', () {
      expect(
        () => validate('findByTitleTrue', []),
        throwsQuery('need a bool'),
      );
      expect(() => validate('findByYearFalse', []), throwsQuery('need a bool'));
      validate('findByInStockFalse', []);
    });

    test('In needs a collection of fitting elements', () {
      expect(
        () => validate('findByYearIn', [param('y', integer)]),
        throwsQuery('must be a List, Set or Iterable'),
      );
      expect(
        () => validate('findByYearIn', [param('y', string)]),
        throwsQuery('must be a List, Set or Iterable'),
      );
      expect(
        () => validate('findByYearIn', [
          param('y', const ListType<String>(string)),
        ]),
        throwsQuery('elements'),
      );
      validate('findByYearIn', [param('y', const ListType<int>(integer))]);
      validate('findByYearNotIn', [param('y', const SetType<int>(integer))]);
      validate('findByYearIn', [
        param('y', const GenericType<Iterable<int>>([ClassType<int>()])),
      ]);
      validate('findByAuthorIdIn', [param('y', const ListType<int>(integer))]);
    });

    test('Sort and Pageable are excluded wherever they are', () {
      const sort = ClassType<Sort>();
      const pageable = ClassType<Pageable>();
      validate('findByTitleAndYear', [
        param('t', string),
        param('s', sort),
        param('y', integer),
      ]);
      validate('findByTitleAndYear', [
        param('p', pageable),
        param('t', string),
        param('y', integer),
      ]);
      validate('findByTitleAndYear', [
        param('t', string),
        param('y', integer),
        param('p', pageable),
      ]);
      expect(
        () => validate('findByTitleAndYear', [
          param('t', string),
          param('p', pageable),
        ]),
        throwsQuery('needs 2'),
      );
    });

    test('parameters are consumed in order, argumentCount each', () {
      const pageable = ClassType<Pageable>();
      // Between takes two; the Pageable in the middle does not count.
      validate('findByYearBetweenAndTitle', [
        param('a', integer),
        param('p', pageable),
        param('b', integer),
        param('t', string),
      ]);
      expect(
        () => validate('findByYearBetweenAndTitle', [
          param('a', integer),
          param('b', string),
          param('t', string),
        ]),
        throwsQuery("parameter 'b'"),
      );
      expect(
        () => validate('findByTitleAndYearBetween', [
          param('a', integer),
          param('b', integer),
          param('c', integer),
        ]),
        throwsQuery("parameter 'a'"),
      );
    });

    test('Sort and Pageable together, or twice, are errors', () {
      expect(
        () => validate('findByTitle', [
          param('t', string),
          param('s', const ClassType<Sort>()),
          param('p', const ClassType<Pageable>()),
        ]),
        throwsQuery('Pageable and a Sort'),
      );
      expect(
        () => validate('findByTitle', [
          param('t', string),
          param('s', const ClassType<Sort>()),
          param('s2', const ClassType<Sort>()),
        ]),
        throwsQuery('more than one Sort'),
      );
      expect(
        () => validate('countByTitle', [
          param('t', string),
          param('s', const ClassType<Sort>()),
        ], returnType: integer),
        throwsQuery('only allowed on a find'),
      );
    });

    test('a Pageable with Top is allowed', () {
      validate('findTop3ByTitle', [
        param('t', string),
        param('p', const ClassType<Pageable>()),
      ]);
    });
  });

  group('validate return type', () {
    const book = ClassType<Book>();
    const books = ListType<Book>(book);
    const page = GenericType<Page<Book>>([book]);
    const slice = GenericType<Slice<Book>>([book]);
    const stream = GenericType<Stream<Book>>([book]);
    const iterable = GenericType<Iterable<Book>>([book]);
    final args = [param('t', string)];
    final paged = [param('t', string), param('p', const ClassType<Pageable>())];

    test('find', () {
      for (final type in <TypeInfo<Object?>>[
        book,
        const ClassType<Book>(nullable: true),
        books,
        const SetType<Book>(book),
        iterable,
        stream,
      ]) {
        validate(
          'findByTitle',
          args,
          returnType: type,
          isFuture: type != stream,
        );
      }
      validate('findByTitle', paged, returnType: page);
      validate('findByTitle', paged, returnType: slice);
      validate('findByTitle', paged);
      validate('findByTitle', args, returnType: stream, isFuture: false);
    });

    test('Page and Slice need a Pageable', () {
      expect(
        () => validate('findByTitle', args, returnType: page),
        throwsQuery('needs a Pageable'),
      );
      expect(
        () => validate('findByTitle', args, returnType: slice),
        throwsQuery('needs a Pageable'),
      );
    });

    test('Stream is not a Future', () {
      expect(
        () => validate('findByTitle', args, returnType: stream),
        throwsQuery('already asynchronous'),
      );
    });

    test('projections and other types are rejected', () {
      for (final type in <TypeInfo<Object?>>[
        const ClassType<Author>(),
        const ListType<Author>(ClassType<Author>()),
        string,
        const GenericType<Page<Author>>([ClassType<Author>()]),
      ]) {
        expect(
          () => validate('findByTitle', paged, returnType: type),
          throwsQuery('must return Book'),
        );
      }
    });

    test('count, exists, delete', () {
      validate('countByTitle', args, returnType: integer);
      expect(
        () => validate('countByTitle', args, returnType: string),
        throwsQuery('must return int'),
      );
      validate('existsByTitle', args, returnType: const ClassType<bool>());
      expect(
        () => validate('existsByTitle', args, returnType: integer),
        throwsQuery('must return bool'),
      );
      validate('deleteByTitle', args, returnType: const DynamicType.forVoid());
      validate('removeByTitle', args, returnType: integer);
      validate('deleteByTitle', args);
      expect(
        () => validate('deleteByTitle', args, returnType: string),
        throwsQuery('must return void'),
      );
      expect(
        () => validate(
          'deleteByTitle',
          args,
          returnType: const ListType<Author>(ClassType<Author>()),
        ),
        throwsQuery('must return void'),
      );
    });
  });
}
