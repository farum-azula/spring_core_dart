import 'package:spring_boot_starter_data/src/repository/sort.dart';

/// A repository method name understood as a query, Spring Data's way:
/// `findTop5ByTitleContainingIgnoreCaseAndYearGreaterThanOrderByYearDesc`
/// is a [subject] (`find`, the first 5), a [predicate] (two parts joined by
/// `And`) and a static [sort] (`year` descending).
///
/// The parser builds it, checking every property against the entity;
/// a store turns it into SQL, a PostgREST filter, or an in-memory filter.
///
/// Spring (Java): `org.springframework.data.repository.query.parser.PartTree`.
final class PartTree {
  /// The parsed method [methodName].
  const PartTree({
    required this.methodName,
    required this.subject,
    required this.predicate,
    this.sort = Sort.unsorted,
  });

  /// The method's name, for messages.
  final String methodName;

  /// What the method does with the matching aggregates.
  final Subject subject;

  /// Which aggregates match: alternatives (`Or`) of conjunctions (`And`);
  /// no alternative at all matches every aggregate (`findAll...`,
  /// `countBy` with nothing after `By`).
  final List<OrPart> predicate;

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

/// One condition of a query method name: a property path, an operator
/// ([type]) and whether case is ignored.
///
/// Spring (Java): `org.springframework.data.repository.query.parser.Part`.
final class Part {
  /// The condition [type] on the property at [path].
  const Part(this.path, this.type, {this.ignoreCase = false});

  /// The property, by Dart property names from the entity (one name; a
  /// path into an embedded object later, as `address.city`).
  final List<String> path;

  /// The operator.
  final PartType type;

  /// Whether the comparison ignores case (`IgnoreCase`, `AllIgnoreCase`):
  /// both sides lower-cased. Only for `String` properties.
  final bool ignoreCase;

  /// The path as one string, `address.city`.
  String get property => path.join('.');

  @override
  bool operator ==(Object other) =>
      other is Part &&
      _listEquals(other.path, path) &&
      other.type == type &&
      other.ignoreCase == ignoreCase;

  @override
  int get hashCode => Object.hash(Object.hashAll(path), type, ignoreCase);

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

  /// The suffixes that write it. The parser tries the types in the order of
  /// this enum (as Spring's `Part.Type.ALL`), so `NotIn` is found before
  /// `In` and `IsNotNull` before `IsNull`.
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
