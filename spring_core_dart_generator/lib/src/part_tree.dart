/// What the build knows of a derived query: a repository method name read
/// as a query, `findTop5ByTitleContainingIgnoreCaseOrderByYearDesc`, in the
/// shape the generated code writes it (`PartTree`, `Part`, ... of
/// `spring_boot_starter_data`, which the generator only knows by name).
library;

/// How a query method's result is shaped.
enum ResultShape {
  /// `List`, `Iterable`: all results.
  list,

  /// `Set`: all results, once each.
  set,

  /// `Page`: a window and the total.
  page,

  /// `Slice`: a window and whether another follows.
  slice,

  /// `Stream`: the results as they arrive.
  stream,

  /// The entity itself: one result.
  single,
}

/// What a query method does with the rows its predicate matches.
///
/// Spring (Java): `PartTree.Subject`.
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

/// The subject of a method name: [kind], at most [maxResults] rows (`null`
/// for all) and [distinct] when `Distinct` is written.
final class SubjectModel {
  /// A subject of [kind].
  const SubjectModel(this.kind, {this.maxResults, this.distinct = false});

  /// Find, count, test or delete.
  final SubjectKind kind;

  /// The `First`/`Top` limit (`findTop5By...` is 5, `findFirstBy...` is 1).
  final int? maxResults;

  /// Whether `Distinct` was written.
  final bool distinct;

  /// Whether this is the subject every method has by default: a plain find.
  bool get isDefault =>
      kind == SubjectKind.find && maxResults == null && !distinct;
}

/// The operator of a [PartModel], with the keywords that write it and how
/// many method parameters it consumes. The parser tries the kinds in the
/// order of this enum (as Spring's `Part.Type.ALL`), so `NotIn` is found
/// before `In` and `IsNotNull` before `IsNull`; each name is the one of
/// `PartType` in the starter.
///
/// Spring (Java): `Part.Type`.
enum PartKind {
  /// `Between`: two parameters.
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

  /// `NotLike`, `IsNotLike`.
  notLike(1, ['IsNotLike', 'NotLike']),

  /// `Like`, `IsLike`.
  like(1, ['IsLike', 'Like']),

  /// `StartingWith`, `IsStartingWith`, `StartsWith`.
  startingWith(1, ['IsStartingWith', 'StartingWith', 'StartsWith']),

  /// `EndingWith`, `IsEndingWith`, `EndsWith`.
  endingWith(1, ['IsEndingWith', 'EndingWith', 'EndsWith']),

  /// `NotContaining`, `IsNotContaining`, `NotContains`.
  notContaining(1, ['IsNotContaining', 'NotContaining', 'NotContains']),

  /// `Containing`, `IsContaining`, `Contains`.
  containing(1, ['IsContaining', 'Containing', 'Contains']),

  /// `NotIn`, `IsNotIn`.
  notIn(1, ['IsNotIn', 'NotIn']),

  /// `In`, `IsIn`.
  in_(1, ['IsIn', 'In']),

  /// `True`, `IsTrue`.
  isTrue(0, ['IsTrue', 'True']),

  /// `False`, `IsFalse`.
  isFalse(0, ['IsFalse', 'False']),

  /// `Not`, `IsNot`.
  negatingSimpleProperty(1, ['IsNot', 'Not']),

  /// `Is`, `Equals`, or no keyword.
  simpleProperty(1, ['Is', 'Equals']);

  PartKind(this.argumentCount, this.keywords);

  /// How many method parameters the operator consumes.
  final int argumentCount;

  /// The suffixes that write it.
  final List<String> keywords;
}

/// One condition of a method name: the property, the operator and whether
/// case is ignored.
final class PartModel {
  /// The condition [kind] on [property].
  const PartModel(this.property, this.kind, {this.ignoreCase = false});

  /// The Dart name of the entity's property.
  final String property;

  /// The operator.
  final PartKind kind;

  /// Whether both sides are lower-cased (`IgnoreCase`, `AllIgnoreCase`).
  final bool ignoreCase;
}

/// Conditions joined by `And`: one alternative of an `Or`.
final class OrPartModel {
  /// The conjunction of [parts].
  const OrPartModel(this.parts);

  /// The conditions that must all hold.
  final List<PartModel> parts;
}

/// One property of an `OrderBy` clause.
final class SortOrderModel {
  /// Sorts by [property], descending when [descending].
  const SortOrderModel(this.property, {this.descending = false});

  /// The Dart name of the entity's property.
  final String property;

  /// Whether `Desc` is written.
  final bool descending;
}

/// A method name read as a query: the subject, the alternatives of the
/// predicate and the order written in the name.
///
/// ```dart
/// // findTop5ByTitleContainingIgnoreCaseAndYearGreaterThanOrderByYearDesc
/// // is written as
/// static const _find = PartTree(r'findTop5By...',
///   [OrPart([Part(r'title', PartType.containing, ignoreCase: true),
///            Part(r'year', PartType.greaterThan)])],
///   subject: Subject(SubjectKind.find, maxResults: 5),
///   sort: Sort([SortOrder.desc(r'year')]));
/// ```
///
/// Spring (Java):
/// `org.springframework.data.repository.query.parser.PartTree`.
final class PartTreeModel {
  /// The tree of [methodName].
  const PartTreeModel(
    this.methodName,
    this.subject,
    this.predicate,
    this.sort,
  );

  /// The method's name.
  final String methodName;

  /// What the method does with the matches.
  final SubjectModel subject;

  /// The alternatives (`Or`) of conjunctions (`And`); none matches every
  /// row (`findAllBy`).
  final List<OrPartModel> predicate;

  /// The order written in the name; none for an unsorted query.
  final List<SortOrderModel> sort;

  /// Every part, in the order of the parameters they consume.
  Iterable<PartModel> get parts => predicate.expand((or) => or.parts);

  /// How many method parameters the predicate consumes.
  int get parameterCount =>
      parts.fold(0, (sum, part) => sum + part.kind.argumentCount);
}
