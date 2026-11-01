import 'package:spring_boot_starter_data/src/repository/sort.dart';

/// A repository method name understood as a query, Spring Data's way:
/// `findTop5ByTitleContainingIgnoreCaseAndYearGreaterThanOrderByYearDesc`
/// is a [subject] (`find`, the first 5), a [predicate] (two parts joined by
/// `And`) and a static [sort] (`year` descending).
///
/// The build parses the name, checks every property against the entity, and
/// writes the tree as a constant in the generated repository class, so a
/// wrong name is a build error; nothing is parsed when the application
/// starts. A store turns the tree into SQL or an in-memory filter.
///
/// ```dart
/// // findByTitleAndYearGreaterThan
/// const tree = PartTree(r'findByTitleAndYearGreaterThan', [
///   OrPart([Part(r'title'), Part(r'year', PartType.greaterThan)]),
/// ]);
/// ```
///
/// Spring (Java): `org.springframework.data.repository.query.parser.PartTree`.
final class PartTree {
  /// The tree of the method [methodName]: [predicate] and [subject] as its
  /// name says them, and the order its `OrderBy` gives.
  const PartTree(
    this.methodName,
    this.predicate, {
    this.subject = const Subject(SubjectKind.find),
    this.sort = Sort.unsorted,
  });

  /// The method's name, for messages.
  final String methodName;

  /// Which aggregates match: alternatives (`Or`) of conjunctions (`And`);
  /// no alternative at all matches every aggregate (`findAll...`,
  /// `countBy` with nothing after `By`).
  final List<OrPart> predicate;

  /// What the method does with the matching aggregates.
  final Subject subject;

  /// The order written in the name (`OrderByTitleAsc`); a `Sort` or
  /// `Pageable` parameter is applied after it.
  final Sort sort;

  /// Every [Part] of the predicate, in the order of the method's
  /// parameters they consume.
  Iterable<Part> get parts => predicate.expand((or) => or.parts);

  /// How many method parameters the predicate consumes, in order from the
  /// first.
  int get parameterCount =>
      parts.fold(0, (sum, part) => sum + part.type.argumentCount);
}

/// What a query method does with the aggregates its predicate matches.
///
/// Spring (Java): `PartTree.Subject`.
final class Subject {
  /// A subject of [kind], at most [maxResults] results (null: all),
  /// [distinct] when the name says so.
  const Subject(this.kind, {this.maxResults, this.distinct = false});

  /// Find, count, test or delete.
  final SubjectKind kind;

  /// The `First`/`Top` limit (`findTop5By...` → 5, `findFirstBy...` → 1);
  /// null for no limit.
  final int? maxResults;

  /// Whether `Distinct` was written.
  final bool distinct;

  @override
  bool operator ==(Object other) =>
      other is Subject &&
      other.kind == kind &&
      other.maxResults == maxResults &&
      other.distinct == distinct;

  @override
  int get hashCode => Object.hash(kind, maxResults, distinct);

  @override
  String toString() =>
      'Subject(${kind.name}'
      '${maxResults == null ? '' : ', max $maxResults'}'
      '${distinct ? ', distinct' : ''})';
}

/// The prefix of a query method name.
enum SubjectKind {
  /// `find`, `read`, `get`, `query`, `search`, `stream`: load the matches.
  find,

  /// `count`: the number of matches.
  count,

  /// `exists`: whether any match.
  exists,

  /// `delete`, `remove`: delete the matches.
  delete,
}

/// Parts joined by `And`.
///
/// Spring (Java): `PartTree.OrPart` (a conjunction, despite its name: one
/// alternative of the `Or`).
final class OrPart {
  /// The conjunction of [parts].
  const OrPart(this.parts);

  /// The parts, all of which must hold.
  final List<Part> parts;

  @override
  bool operator ==(Object other) =>
      other is OrPart && _listEquals(other.parts, parts);

  @override
  int get hashCode => Object.hashAll(parts);

  @override
  String toString() => parts.join(' and ');
}

/// One condition of a query method name: a property, an operator ([type])
/// and whether case is ignored.
///
/// Dart has no optional positional and named parameters together, so
/// [ignoreCase] is the third positional one: `Part(r'title', PartType.like,
/// true)`.
///
/// Spring (Java): `org.springframework.data.repository.query.parser.Part`.
final class Part {
  /// The condition [type] (equal by default) on [property], comparing
  /// case-insensitively when [ignoreCase].
  const Part(
    this.property, [
    this.type = PartType.simpleProperty,
    this.ignoreCase = false,
  ]);

  /// The property, by its Dart name in the entity (one name; a path into an
  /// embedded object later, as `address.city`).
  final String property;

  /// The operator.
  final PartType type;

  /// Whether the comparison ignores case (`IgnoreCase`, `AllIgnoreCase`):
  /// both sides lower-cased. Only for `String` properties.
  final bool ignoreCase;

  /// The property's names, `address.city` as `[address, city]`.
  List<String> get path => property.split('.');

  @override
  bool operator ==(Object other) =>
      other is Part &&
      other.property == property &&
      other.type == type &&
      other.ignoreCase == ignoreCase;

  @override
  int get hashCode => Object.hash(property, type, ignoreCase);

  @override
  String toString() =>
      '$property ${type.name}${ignoreCase ? ' (ignoring case)' : ''}';
}

/// The operator of a [Part], with the keywords that write it and how many
/// method parameters it consumes.
///
/// Spring (Java): `Part.Type`.
enum PartType {
  /// `Between`: `lower <= p <= upper` (two parameters).
  between(2, ['IsBetween', 'Between']),

  /// `IsNotNull`, `NotNull`.
  isNotNull(0, ['IsNotNull', 'NotNull']),

  /// `IsNull`, `Null`.
  isNull(0, ['IsNull', 'Null']),

  /// `LessThan`, `IsLessThan`, `Before`, `IsBefore`.
  lessThan(1, ['IsLessThan', 'LessThan', 'IsBefore', 'Before']),

  /// `LessThanEqual`, `IsLessThanEqual`.
  lessThanEqual(1, ['IsLessThanEqual', 'LessThanEqual']),

  /// `GreaterThan`, `IsGreaterThan`, `After`, `IsAfter`.
  greaterThan(1, ['IsGreaterThan', 'GreaterThan', 'IsAfter', 'After']),

  /// `GreaterThanEqual`, `IsGreaterThanEqual`.
  greaterThanEqual(1, ['IsGreaterThanEqual', 'GreaterThanEqual']),

  /// `NotLike`, `IsNotLike`: the parameter is a pattern (`%`, `_`).
  notLike(1, ['IsNotLike', 'NotLike']),

  /// `Like`, `IsLike`: the parameter is a pattern (`%`, `_`).
  like(1, ['IsLike', 'Like']),

  /// `StartingWith`, `IsStartingWith`, `StartsWith`: a prefix, its own `%`
  /// and `_` matched literally.
  startingWith(1, ['IsStartingWith', 'StartingWith', 'StartsWith']),

  /// `EndingWith`, `IsEndingWith`, `EndsWith`: a suffix.
  endingWith(1, ['IsEndingWith', 'EndingWith', 'EndsWith']),

  /// `NotContaining`, `IsNotContaining`, `NotContains`: no such substring.
  notContaining(1, ['IsNotContaining', 'NotContaining', 'NotContains']),

  /// `Containing`, `IsContaining`, `Contains`: a substring.
  containing(1, ['IsContaining', 'Containing', 'Contains']),

  /// `NotIn`, `IsNotIn`: not among a collection.
  notIn(1, ['IsNotIn', 'NotIn']),

  /// `In`, `IsIn`: among a collection.
  in_(1, ['IsIn', 'In']),

  /// `True`, `IsTrue`.
  isTrue(0, ['IsTrue', 'True']),

  /// `False`, `IsFalse`.
  isFalse(0, ['IsFalse', 'False']),

  /// `Not`, `IsNot`: not equal.
  negatingSimpleProperty(1, ['IsNot', 'Not']),

  /// `Is`, `Equals`, or no keyword: equal (null parameter: `is null`, as
  /// Spring).
  simpleProperty(1, ['Is', 'Equals']);

  PartType(this.argumentCount, this.keywords);

  /// How many method parameters the operator consumes.
  final int argumentCount;

  /// The suffixes that write it. The build's parser tries the types in the
  /// order of this enum (as Spring's `Part.Type.ALL`), so `NotIn` is found
  /// before `In` and `IsNotNull` before `IsNull`.
  final List<String> keywords;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
