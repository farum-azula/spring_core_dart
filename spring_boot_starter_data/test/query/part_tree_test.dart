// The constants the build writes for a derived query's name.
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:test/test.dart';

const tree = PartTree(
  'findTop2ByTitleContainingAndYearBetweenOrAuthorOrderByYearDesc',
  [
    OrPart([
      Part('title', PartType.containing, true),
      Part('year', PartType.between),
    ]),
    OrPart([Part('author')]),
  ],
  subject: Subject(SubjectKind.find, maxResults: 2, distinct: true),
  sort: Sort([SortOrder.desc('year')]),
);

Part make(String property) => Part(property);

void main() {
  test('a tree is a constant of its parts', () {
    expect(tree.methodName, startsWith('findTop2By'));
    expect(tree.predicate, hasLength(2));
    expect(
      tree.subject,
      const Subject(SubjectKind.find, maxResults: 2, distinct: true),
    );
    expect(tree.sort.orders, [const SortOrder.desc('year')]);
    expect(
      [for (final part in tree.parts) part.property],
      [
        'title',
        'year',
        'author',
      ],
    );
    // The arguments the parts take: one, two and one.
    expect(tree.parameterCount, 4);
  });

  test('the defaults are a find without a limit, unsorted', () {
    const plain = PartTree('findAllBy', []);
    expect(plain.subject, const Subject(SubjectKind.find));
    expect(plain.sort, Sort.unsorted);
    expect(plain.parameterCount, 0);
  });

  test('a part is equal by default, case-sensitive', () {
    const part = Part('title');
    expect(part.type, PartType.simpleProperty);
    expect(part.ignoreCase, isFalse);
    expect(part, equals(make('title')));
    expect(part, isNot(const Part('title', PartType.simpleProperty, true)));
    expect(part.hashCode, const Part('title').hashCode);
  });

  test('a property path is split at the dots', () {
    expect(const Part('address.city').path, ['address', 'city']);
    expect(const Part('title').path, ['title']);
  });

  test('a const Sort equals the one built at run time', () {
    const sort = Sort([SortOrder.asc('a'), SortOrder.desc('b')]);
    expect(
      sort,
      Sort.byOrders([const SortOrder.asc('a'), const SortOrder.desc('b')]),
    );
    expect(sort.isSorted, isTrue);
    expect(Sort(List<SortOrder>.empty()), Sort.unsorted);
    expect(Sort.byOrders(const []), same(Sort.unsorted));
  });
}
